import AppKit
import ApplicationServices

/// Which mechanism identified the current Resolve project.
enum DetectionTier: String, Sendable {
    case scriptingAPI   // Tier 1 — Resolve Studio only
    case windowTitle    // Tier 2 — Accessibility, Free + Studio
    case manual         // Tier 3 — always available
}

/// Three-tier Resolve project detection. Tier 2 reads the frontmost Resolve
/// window title via Accessibility; Tier 3 is the guaranteed fallback.
/// Tier 1 (scripting API) is stubbed for the pilot — the hook is here, the
/// wire-up to Resolve's Python IPC is a post-pilot task.
@MainActor
final class ProjectDetector {

    private(set) var lastDetectedName: String?
    private(set) var activeTier: DetectionTier = .manual

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
    /// Titles look like "DaVinci Resolve - <Project>" (or just "DaVinci
    /// Resolve" on some screens → nil, keep last known).
    func detectProjectName() -> String? {
        guard accessibilityGranted,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
              }) else { return lastDetectedName }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return lastDetectedName }

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else { return lastDetectedName }

        if let name = Self.projectName(fromWindowTitle: title) {
            lastDetectedName = name
            activeTier = .windowTitle
        }
        return lastDetectedName
    }

    // MARK: - Tier 1 — Resolve scripting API (Studio only)

    /// Resolve ships `fuscript` inside the app bundle; external scripting
    /// answers only on Studio. Free editions simply return nothing and we
    /// stay on Tier 2/3.
    nonisolated static func fuscriptPath() -> String? {
        let p = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fuscript"
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    /// Asks the running Resolve for its current project name. ~3s timeout,
    /// never blocks the main thread, nil on any failure.
    func detectViaScriptingAPI() async -> String? {
        guard let path = Self.fuscriptPath(),
              NSWorkspace.shared.runningApplications.contains(where: {
                  DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
              }) else { return nil }
        let name = await Task.detached(priority: .utility) { () -> String? in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["-l", "lua", "-x",
                "resolve = Resolve(); if resolve then local pm = resolve:GetProjectManager(); if pm then local p = pm:GetCurrentProject(); if p then print(p:GetName()) end end end"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do { try proc.run() } catch { return nil }
            let deadline = Date().addingTimeInterval(3)
            while proc.isRunning && Date() < deadline { usleep(100_000) }
            if proc.isRunning { proc.terminate(); return nil }
            // fuscript prints a banner ("DaVinci Resolve Script Interpreter",
            // copyright line) before the result — the project name is the
            // LAST non-empty line.
            guard let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return nil }
            let lines = raw.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .filter { !$0.contains("Blackmagic Design") && !$0.contains("Script Interpreter") }
            guard let name = lines.last, !name.lowercased().contains("error") else { return nil }
            return name
        }.value
        if let name {
            lastDetectedName = name
            activeTier = .scriptingAPI
        }
        return name
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
