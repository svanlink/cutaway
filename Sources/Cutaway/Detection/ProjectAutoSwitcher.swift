import Foundation

/// When each detection tier runs.
///
/// Pure, so the schedule can be tested. It used to live inside the engine's
/// tick closure in `AppModel.init`, where the only way to check "does Tier 1
/// back off to two minutes once Accessibility is granted" was to read it.
struct DetectionSchedule: Equatable {
    private(set) var tick = 0

    /// Tier 2 is a cheap AX title read.
    static let tier2Every = 5
    /// Tier 1 fires early on a fresh install so the open project is picked up
    /// within seconds rather than after the steady-state interval.
    static let tier1FirstAt = 3
    /// Spawning `fuscript` is the app's heaviest periodic cost. When the cheap
    /// tier is available, the expensive one backs off.
    static let tier1WithAccessibility = 120
    static let tier1WithoutAccessibility = 30

    mutating func advance() { tick += 1 }

    var runsTier2: Bool { tick % Self.tier2Every == 0 }

    func runsTier1(accessibilityGranted: Bool) -> Bool {
        let interval = accessibilityGranted ? Self.tier1WithAccessibility : Self.tier1WithoutAccessibility
        return tick == Self.tier1FirstAt || tick % interval == 0
    }
}

/// Follows Resolve from the engine's tick: Tier 2 by window title, Tier 1 by
/// the scripting API.
@MainActor
final class ProjectAutoSwitcher {
    private let detector: ProjectDetector
    private let engine: DetectionEngine
    private let intent: () -> ManualIntent
    /// (name, mayCreateProject)
    private let onDetected: (String, Bool) -> Void

    private var schedule = DetectionSchedule()
    private var tier1InFlight = false
    private let adobe: AdobeDetector
    /// Ask each Adobe app once per activation, not once per tick.
    private var lastAdobeApp: String?

    init(detector: ProjectDetector, engine: DetectionEngine,
         intent: @escaping () -> ManualIntent,
         onDetected: @escaping (String, Bool) -> Void) {
        self.detector = detector
        self.engine = engine
        self.intent = intent
        self.onDetected = onDetected
        self.adobe = AdobeDetector(log: { [weak engine] kind, detail in
            engine?.logDetection(kind, detail: detail)
        })
    }

    /// An Adobe app came forward. Ask it once, for the document name only.
    ///
    /// SELECT, never create: the answer is a filename, and filenames creating
    /// projects would fill the switcher with versions of one job. If nothing
    /// matches an existing project, the time still counts — it just stays
    /// where the owner put it.
    func applicationActivated(_ bundleID: String?) {
        guard let bundleID, AdobeDocument.namesDocuments(bundleID) else {
            lastAdobeApp = nil
            return
        }
        guard bundleID != lastAdobeApp else { return }
        lastAdobeApp = bundleID
        if case .name(let candidate) = adobe.documentName(forBundleID: bundleID) {
            onDetected(candidate, false)
        }
    }

    func tick() {
        // Detection runs while recording AND while paused for lack of a
        // project — that is how a zero-state install bootstraps itself from
        // whatever is already open in Resolve.
        let active = engine.state == .recording || engine.state == .paused(.noProject)
        guard active else { return }
        schedule.advance()

        if schedule.runsTier2, let detected = detector.detectProjectName() {
            // Tier 2 may only SELECT. Titles carry suffixes and case drift;
            // letting them create would spawn duplicate projects that
            // silently split one job's billing.
            onDetected(detected, false)
        }
        guard schedule.runsTier1(accessibilityGranted: detector.accessibilityGranted),
              !tier1InFlight else { return }
        tier1InFlight = true
        // Stamped BEFORE the request: fuscript takes seconds, and an answer
        // about the world as it was must not overrule a choice the user has
        // made since. (This guard was silently lost once in an edit
        // collision — the ManualIntent unit tests kept passing because they
        // test the struct, not the wiring. DetectionWiringTests pins it.)
        let startedAt = intent().token
        let requestStarted = Date()
        Task { [weak self] in
            let name = await self?.detector.detectViaScriptingAPI()
            await MainActor.run {
                guard let self else { return }
                self.tier1InFlight = false
                self.engine.logDetection("tier1",
                    detail: "name=\(name ?? "nil") took="
                          + String(format: "%.2f", Date().timeIntervalSince(requestStarted)) + "s")
                guard !self.intent().hasMovedSince(startedAt) else { return }
                // Tier 1 is the exact API name — it may create.
                if let name { self.onDetected(name, true) }
            }
        }
    }
}
