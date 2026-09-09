import AppKit
import ApplicationServices
import os

/// Which mechanism identified the current Resolve project.
enum DetectionTier: String, Sendable {
    case scriptingAPI   // Tier 1 — Resolve Studio only
    case windowTitle    // Tier 2 — Accessibility, Free + Studio
    case manual         // Tier 3 — always available
}

/// Three-tier Resolve project detection. Tier 1 asks Resolve's own scripting
/// API (fuscript) for the current project name and is the source of truth;
/// Tier 2 reads the frontmost Resolve window title via Accessibility and may
/// only select an existing project; Tier 3 is the guaranteed manual fallback.
/// Tier 1 returns nil whenever Resolve is not running — that is the early
/// return in detectViaScriptingAPI, not a stub.
@MainActor
final class ProjectDetector {

    private(set) var lastDetectedName: String?
    private(set) var activeTier: DetectionTier = .manual
    /// Did the scripting call actually reach Resolve and come back?
    ///
    /// Distinct from "did it name a project". A machine with External
    /// Scripting off, or a free edition, can never answer — and the clock
    /// must not wait forever for an answer that will not come. A machine that
    /// CAN answer, saying "nothing is open", is a reason to wait.
    private(set) var scriptingReachable = false

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system Accessibility permission dialog (once).
    func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    /// Detected edition, for the UI's detect line.
    func resolveEdition() -> String? {
        guard NSWorkspace.shared.runningApplications.contains(where: {
            DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
        }) else { return nil }
        // Studio ships at a distinct path component; fall back to "Resolve".
        let studioMarker = FileManager.default.fileExists(
            atPath: "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting")
        return studioMarker ? "Resolve Studio" : "Resolve"
    }

    /// Tier 2: parse the project name out of Resolve's focused window title.
    /// Is Resolve running at all? Cheap: no disk, no scripting, just the
    /// running-app list. `resolveEdition()` also stats a support directory,
    /// which is far too much to do on every tick.
    var isResolveRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
        }
    }

    /// A FRESH window-title read, or nil. Never the cached name.
    ///
    /// `detectProjectName()` answers with the last known name when a read
    /// fails, which is right for "what project are we on" and badly wrong for
    /// "what is Resolve showing right now" — a failed read would present a
    /// stale project as observed truth, and the mismatch guard would clear
    /// itself against a name nobody had seen.
    func freshProjectName() -> String? {
        let before = lastDetectedName
        let answer = detectProjectName()
        return answer == before && !titleReadSucceeded ? nil : answer
    }

    /// Set by the last `detectProjectName()` call: did the AX read actually
    /// produce a title this time?
    private(set) var titleReadSucceeded = false

    /// Titles look like "DaVinci Resolve - <Project>" (or just "DaVinci
    /// Resolve" on some screens → nil, keep last known).
    func detectProjectName() -> String? {
        titleReadSucceeded = false
        guard accessibilityGranted,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
              }) else { return lastDetectedName }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // A synchronous AX call into another process blocks THIS one until
        // that process answers. Resolve mid-render can take its time, and the
        // default timeout is generous enough to be felt as a beachball in a
        // menu-bar app that reads every five seconds.
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowValue = windowRef,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return lastDetectedName }
        // `as!` here was a crash waiting for the day AX answers with anything
        // else — an AXValue, a string, nil wrapped in a CFType.
        let window = unsafeDowncast(windowValue, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else { return lastDetectedName }

        if let name = Self.projectName(fromWindowTitle: title) {
            lastDetectedName = name
            activeTier = .windowTitle
            titleReadSucceeded = true
        }
        return lastDetectedName
    }

    // MARK: - Tier 1 — Resolve scripting API (Studio only)

    /// Resolve ships `fuscript` inside the app bundle; external scripting
    /// answers only on Studio. Free editions simply return nothing and we
    /// stay on Tier 2/3.
    /// Candidate fuscript locations: wherever LaunchServices says Resolve
    /// actually lives (covers nonstandard installs), then the stock paths.
    nonisolated static func fuscriptCandidates() -> [String] {
        var roots = DetectionInput.resolveBundleIDs.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path
        }
        roots.append("/Applications/DaVinci Resolve/DaVinci Resolve.app")
        roots.append(NSHomeDirectory() + "/Applications/DaVinci Resolve/DaVinci Resolve.app")
        return roots.map { $0 + "/Contents/Libraries/Fusion/fuscript" }
    }

    nonisolated static func fuscriptPath(from candidates: [String]? = nil) -> String? {
        (candidates ?? fuscriptCandidates())
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Asks the running Resolve for its current project name. 8s timeout
    /// (see below), never blocks the main thread, nil on any failure —
    /// including the common one: Resolve is not running.
    func detectViaScriptingAPI() async -> String? {
        guard let path = Self.fuscriptPath(),
              NSWorkspace.shared.runningApplications.contains(where: {
                  DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
              }) else { return nil }
        let outcome = await Task.detached(priority: .utility) { () -> (ran: Bool, name: String?) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["-l", "lua", "-x",
                "resolve = Resolve(); if resolve then local pm = resolve:GetProjectManager(); if pm then local p = pm:GetCurrentProject(); if p then print(p:GetName()) end end end"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do { try proc.run() } catch { return (false, nil) }
            // 8s, not 3: fuscript answers in 0.04s WARM, but the first live
            // end-to-end run (2026-08-23) produced no project inside a 14s
            // window, and a cold spawn blowing a 3s deadline — with the retry
            // landing 30s later — is the only theory that fits. This call is
            // already async, off the main thread, and fires every 30–120s;
            // patience here costs nothing and a kill costs a detection.
            // Wait without parking a cooperative-pool thread: the handler
            // fires on exit, a timer covers the deadline.
            let finished = await withCheckedContinuation { (k: CheckedContinuation<Bool, Never>) in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                let resumeOnce: @Sendable (Bool) -> Void = { ok in
                    resumed.withLock { done in
                        if !done { done = true; k.resume(returning: ok) }
                    }
                }
                proc.terminationHandler = { _ in resumeOnce(true) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                    if proc.isRunning { proc.terminate() }
                    resumeOnce(false)
                }
                if !proc.isRunning { resumeOnce(true) }
            }
            guard finished else { return (false, nil) }
            // fuscript prints a banner ("DaVinci Resolve Script Interpreter",
            // copyright line) before the result — the project name is the
            // LAST non-empty line.
            guard let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return (true, nil) }
            let lines = raw.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .filter { !$0.contains("Blackmagic Design") && !$0.contains("Script Interpreter") }
            // hasPrefix, not contains: a project called "Terror Doc"
            // contains "error", and was silently undetectable forever.
            guard let name = lines.last, !name.lowercased().hasPrefix("error") else { return (true, nil) }
            return (true, name)
        }.value
        scriptingReachable = outcome.ran
        if let name = outcome.name {
            lastDetectedName = name
            activeTier = .scriptingAPI
        }
        return outcome.name
    }

    /// A name, or nil when the anchor is telling us it has nothing open.
    ///
    /// Resolve reports "Untitled Project" when no project is loaded. Treating
    /// that as a project name is how a stray project called "Untitled
    /// Project" was created once already, and it is what turned "Resolve is
    /// open with nothing in it" into a billable mismatch instead of a wait.
    nonisolated static func meaningfulName(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.lowercased() != "untitled project" else { return nil }
        return trimmed
    }

    /// Pure, testable title parser.
    nonisolated static func projectName(fromWindowTitle title: String) -> String? {
        let separators = [" - ", " — "]
        for sep in separators {
            if let range = title.range(of: sep) {
                let candidate = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty, candidate.lowercased() != "davinci resolve" {
                    return candidate
                }
            }
        }
        return nil
    }
}
