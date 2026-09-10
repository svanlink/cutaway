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

    /// - Parameter anchorIsFrontmost: Resolve is the app in front, so Tier 1
    ///   is the only tier that can answer the question the clock turns on.
    ///
    /// Backing off to two minutes whenever Accessibility was granted had the
    /// dependency backwards: `anchorNamedAProject` has exactly one writer,
    /// this poll, and Tier 2 cannot substitute — a Resolve window titled just
    /// "DaVinci Resolve" parses to nil, so the cheap tier is silent on the
    /// one question at issue. Closing a project and leaving Resolve open
    /// therefore billed up to two minutes of nothing to the project just
    /// closed, and opening one held the clock for up to two minutes of real
    /// editing. Granting the permission that makes the cheap tier work
    /// slowed the only tier that could answer, by four times.
    ///
    /// So the back-off applies only when Resolve is NOT in front — which is
    /// when the flag is not load-bearing and when the owner is not editing
    /// anyway. `fuscript` spawns land during active use, not at idle.
    func runsTier1(accessibilityGranted: Bool, anchorIsFrontmost: Bool = false) -> Bool {
        let interval = accessibilityGranted && !anchorIsFrontmost
            ? Self.tier1WithAccessibility : Self.tier1WithoutAccessibility
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
    /// Tier 1 answered, and the answer was "no project is open".
    private let onNoProject: () -> Void

    private var schedule = DetectionSchedule()
    private var tier1InFlight = false

    init(detector: ProjectDetector, engine: DetectionEngine,
         intent: @escaping () -> ManualIntent,
         onDetected: @escaping (String, Bool) -> Void,
         onNoProject: @escaping () -> Void = {}) {
        self.detector = detector
        self.engine = engine
        self.intent = intent
        self.onDetected = onDetected
        self.onNoProject = onNoProject
    }

    /// Deliberately gone: Adobe apps do not name projects.
    ///
    /// A build on 2026-09-08 asked Photoshop, Illustrator, InDesign and
    /// After Effects for their open document and offered it as a project.
    /// The owner's rule, and it is the better rule: **DaVinci Resolve is the
    /// source of truth.** An Adobe app being frontmost proves someone is
    /// working; it never says on what. While Resolve is on project A, work
    /// in After Effects belongs to A — no document name, no Automation
    /// prompt, no second opinion to disagree with Resolve.

    /// Detection observes the world unless the owner has switched it off.
    ///
    /// This used to enumerate the states detection was allowed to run in, and
    /// that list trapped itself TWICE. First `.projectMismatch` was missing:
    /// the pause stopped the only mechanism that could learn Resolve had
    /// moved back, so the clock stayed held until Cutaway was relaunched.
    /// The comment written at that fix — "a guard that cannot observe its own
    /// release condition is a trap, not a guard" — was then proved right
    /// again the next day by `.awaitingProject`, whose ONLY writer lives
    /// inside this guard, so Resolve-only work after a restart billed zero.
    ///
    /// So the list is gone. Deny two states, allow the rest: a manual pause
    /// is sacred, and there is nothing to observe while the Mac is asleep.
    /// Any state added later is observable by default, which is the safe
    /// direction — the failure mode of watching too often is a 40 ms
    /// subprocess every 30 seconds; the failure mode of watching too rarely
    /// is a clock that cannot unstick itself.
    nonisolated static func observes(_ state: DetectionState) -> Bool {
        state != .paused(.manual) && state != .paused(.systemSleep)
    }

    func tick() {
        guard Self.observes(engine.state) else { return }
        schedule.advance()

        // freshProjectName, not detectProjectName. The latter answers with
        // the LAST KNOWN name on every failure path, which is right for
        // "what project are we on" and wrong for "what is Resolve showing
        // right now" — it re-asserted a stale name as an observation, and
        // the mismatch guard then cleared itself against a name nobody had
        // seen. Written for exactly this and left unwired until now.
        if schedule.runsTier2, let detected = detector.freshProjectName() {
            // Tier 2 may only SELECT. Titles carry suffixes and case drift;
            // letting them create would spawn duplicate projects that
            // silently split one job's billing.
            onDetected(detected, false)
        }
        guard schedule.runsTier1(accessibilityGranted: detector.accessibilityGranted,
                                 anchorIsFrontmost: engine.anchorIsFrontmost),
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
                // "Untitled Project" means Resolve has nothing loaded. It is
                // not a name, and treating it as one is what turned "Resolve
                // is open and empty" into a billable mismatch.
                let named = ProjectDetector.meaningfulName(name)
                self.engine.logDetection("tier1",
                    detail: "name=\(name ?? "nil") took="
                          + String(format: "%.2f", Date().timeIntervalSince(requestStarted)) + "s")
                // A reply of any kind proves the anchor CAN be asked on this
                // Mac; the content of the reply says whether it is on a
                // project. Both are needed: the first stops the clock being
                // held hostage on a machine where scripting is off, the
                // second stops it running before Resolve has said anything.
                // Both directions. This only ever wrote `true`, so a Mac that
                // stopped being able to answer — scripting switched off, a
                // downgrade to the free edition — kept a latched flag that
                // held the clock for an answer that could no longer come.
                self.engine.anchorCanNameProjects = self.detector.scriptingReachable
                if self.detector.scriptingReachable {
                    // Remembered, because it is a fact about this Mac, not
                    // about this launch. Otherwise every start has a window
                    // between "Resolve is frontmost" and the first Tier-1
                    // reply in which the clock would run on the old
                    // assumption — smaller than the thirty seconds that
                    // caused this, but the same bug.
                    Prefs.set(true, forKey: "anchorCanNameProjects")
                } else if Prefs.bool(forKey: "anchorCanNameProjects") {
                    Prefs.set(false, forKey: "anchorCanNameProjects")
                }
                self.engine.anchorNamedAProject = named != nil
                // A reachable Resolve saying "nothing loaded" is evidence,
                // and it was thrown away: only a NAME reached the app, so the
                // last one stood until Resolve quit. See
                // `AppModel.anchorHasNoProjectOpen`.
                if self.detector.scriptingReachable, named == nil { self.onNoProject() }
                guard !self.intent().hasMovedSince(startedAt) else { return }
                // Tier 1 is the exact API name — it may create.
                if let named { self.onDetected(named, true) }
            }
        }
    }
}
