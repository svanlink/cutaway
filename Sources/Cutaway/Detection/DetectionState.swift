import Foundation

/// Why the timer is not recording.
enum PauseReason: String, Sendable, Codable {
    case manual
    case systemSleep
    case noProject
    /// DaVinci Resolve has a project open that is NOT the one being
    /// recorded, and nobody has said where it belongs yet.
    ///
    /// This outranks recording, always. On 2026-09-08 Resolve sat on
    /// "2026-08-2_BuildingBridges_OpeningFilm" for twelve minutes while the
    /// timer quietly credited every second of it to a different client's
    /// project. Time that lands on the wrong invoice is worse than time that
    /// lands nowhere: the second is a gap you notice, the first is a lie you
    /// send.
    case projectMismatch
    /// The anchor is open but has not said which project it is on.
    ///
    /// Not the same as `.noProject` (nothing selected in Cutaway) and not the
    /// same as `.projectMismatch` (Resolve is on a DIFFERENT project). This
    /// is "Resolve is up, nothing loaded" — the state on every launch, before
    /// a project is opened.
    case awaitingProject
    case notFrontmost
    case inputIdle
}

/// How a manual pause ends when anchor work is detected again.
enum AutoResumeMode: String, Sendable, CaseIterable {
    case off, ask, auto
}

enum DetectionState: Equatable, Sendable {
    case recording
    case paused(PauseReason)
}

/// WHY the clock is still running. `.recording` alone is opaque: it looks
/// identical whether Resolve is in front or a browser is holding the clock up
/// inside the research window — and that window expires silently, so the user
/// finds out only by noticing the timer stopped. The app is careful not to
/// over-bill; it should be equally clear about when it is about to stop.
enum RecordingSource: Equatable, Sendable {
    /// An anchor app is frontmost — this runs as long as the work does.
    case anchor
    /// A satellite app is sustaining the clock, and will stop when the
    /// research window closes.
    case satellite(secondsLeft: TimeInterval)

    var isTimeLimited: Bool {
        if case .satellite = self { return true }
        return false
    }
}

/// Everything the state machine needs for one evaluation. Pure data — the
/// live probes (NSWorkspace, CGEventSource) fill this in; tests build it directly.
struct DetectionInput: Sendable {
    var frontmostBundleID: String?
    var secondsSinceInput: TimeInterval
    var idleThreshold: TimeInterval
    var manuallyPaused: Bool
    var isAsleep: Bool
    var hasActiveProject: Bool
    /// Resolve is showing a project that is not the selected one. Set by the
    /// app from Tier-1/Tier-2 detection; the state machine only obeys it.
    var projectMismatch: Bool = false
    /// ANCHOR apps (prefix-matched): the toolchain that proves a work block —
    /// they can START recording and refresh the research window.
    var workAppPrefixes: [String] = []
    /// Is any workflow app still RUNNING? Not frontmost — running.
    ///
    /// Defaults to true so a caller that does not know keeps the behaviour it
    /// had; the engine always knows.
    var anchorAppRunning: Bool = true
    /// Has the anchor told us which project it is on?
    ///
    /// Launching Resolve is not opening a project. The clock used to start
    /// the moment Resolve became frontmost, against whatever was selected
    /// last — so a launch with no project open billed the previous client
    /// until the mismatch card caught it half a minute later.
    ///
    /// Defaults to true so a caller that does not know keeps the behaviour it
    /// had; the engine always knows.
    var anchorNamedAProject: Bool = true
    /// CAN the anchor be asked at all? False on a Resolve that has External
    /// Scripting off, or a free edition. Waiting for an answer that can never
    /// come would make the app useless rather than careful, so there the old
    /// behaviour stands.
    var anchorCanNameProjects: Bool = true
    /// SATELLITE apps (browsers, LLMs, mail, files): research/comms that
    /// SUSTAIN recording, but only while the research window is open.
    var satellitePrefixes: [String] = []
    /// True while within the research window of the last anchor activity —
    /// computed by the engine, consumed here.
    var satelliteWindowOpen: Bool = false
    /// True while an anchor app is provably burning cpu (a render/export) and
    /// the user has opted into billing that. Suppresses the idle pause ONLY —
    /// manual pause, sleep and leaving the work context still outrank it.

    /// Resolve ships under one bundle id, but keep this a set so App Store /
    /// regional variants can be added without touching logic.
    static let resolveBundleIDs: [String] = [
        "com.blackmagic-design.DaVinciResolve",
        "com.blackmagic-design.DaVinciResolveLite",
        "com.blackmagic-design.DaVinciResolveStudio",
    ]

    /// The default anchors: Resolve (all three ids) and the Adobe toolchain.
    /// Adobe bundle ids carry year suffixes (com.adobe.PremierePro.2025) —
    /// prefix matching covers all versions. Resolve used to be an anchor by
    /// fiat, outside this list; now it is IN the list, so a project that
    /// names its own apps can genuinely exclude it (see AnchorSet).
    static let defaultWorkAppPrefixes: [String] = resolveBundleIDs + [
        "com.adobe.AfterEffects",
        "com.adobe.Photoshop",
        "com.adobe.PremierePro",
        "com.adobe.illustrator",
        "com.adobe.Audition",
        // In the picker catalog since per-project apps shipped, but missing
        // here until 2026-09-07 — so it was never pre-ticked on a new project
        // and every InDesign hour was tracked as nothing. Media Encoder and
        // Lightroom Classic stay out on purpose: AME renders unattended, and
        // Lightroom is not part of this editor's delivery chain.
        "com.adobe.InDesign",
    ]

    /// Research & comms: browsers, LLM assistants, mail, file transfer.
    static let defaultSatellitePrefixes: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",   // Arc
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        "com.apple.mail",
        "com.apple.finder",
        "com.getdropbox.dropbox",
    ]

    /// Cleans a user-edited prefix list: trims whitespace, drops empties,
    /// dedupes case-insensitively while preserving order.
    static func sanitizedPrefixes(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.compactMap { raw in
            let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty, seen.insert(p.lowercased()).inserted else { return nil }
            return p
        }
    }

    /// Prefix match against the anchor list — and ONLY the list. Resolve is
    /// no longer special-cased here: it is an entry in the default list, and
    /// a project that leaves it out means it.
    var frontmostIsAnchor: Bool {
        guard let front = frontmostBundleID else { return false }
        return workAppPrefixes.contains { front.hasPrefix($0) }
    }

    var frontmostIsSatellite: Bool {
        guard let front = frontmostBundleID else { return false }
        return satellitePrefixes.contains { front.hasPrefix($0) }
    }

    var isWorkContext: Bool {
        // Research sustains work that is still IN PROGRESS somewhere. With
        // every workflow app closed there is no work in progress, so a
        // browser sustains nothing.
        //
        // Observed 2026-09-08: Resolve was quit at 16:37 and the clock kept
        // running until 16:44 — recording against Claude and then Safari,
        // because the twenty-minute research window was still open. From the
        // owner's chair that is the app billing an evening of reading as
        // editing, and the honest reading of the rule is that the window
        // belongs to a session of work, not to a wall clock.
        frontmostIsAnchor || (frontmostIsSatellite && satelliteWindowOpen && anchorAppRunning)
    }
}

extension DetectionState {
    /// Priority: manual > sleep > noProject > notFrontmost > idle.
    /// Manual outranks all — the user's explicit intent must never be
    /// overridden by automation. Sleep outranks app checks because probe
    /// values are meaningless while the machine sleeps.
    static func evaluate(_ input: DetectionInput) -> DetectionState {
        if input.manuallyPaused { return .paused(.manual) }
        if input.isAsleep { return .paused(.systemSleep) }
        if !input.hasActiveProject { return .paused(.noProject) }
        // Before anything about frontmost apps or idleness: if Resolve is on
        // a different project than the one being recorded, there is no
        // correct project to record TO.
        if input.projectMismatch { return .paused(.projectMismatch) }
        // An anchor that has not named a project has not established a work
        // context. Ranked BELOW mismatch — a known wrong project is more
        // specific than an unknown one — and above everything about frontmost
        // apps and idleness, because none of those matter when there is no
        // project to bill to.
        if input.frontmostIsAnchor, input.anchorCanNameProjects, !input.anchorNamedAProject {
            return .paused(.awaitingProject)
        }
        guard input.isWorkContext else { return .paused(.notFrontmost) }
        if input.secondsSinceInput >= input.idleThreshold {
            return .paused(.inputIdle)
        }
        return .recording
    }
}

extension RecordingSource {
    /// Pure so every branch is testable without an engine.
    static func evaluate(state: DetectionState, input: DetectionInput,
                         lastAnchorActive: Date?, window: TimeInterval,
                         now: Date) -> RecordingSource? {
        guard state == .recording else { return nil }
        if input.frontmostIsAnchor { return .anchor }
        guard input.frontmostIsSatellite, let last = lastAnchorActive else { return nil }
        return .satellite(secondsLeft: max(0, window - now.timeIntervalSince(last)))
    }

    /// What the panel prints. Rounds DOWN, so the number never promises time
    /// the window does not still have.
    var label: String? {
        guard case .satellite(let secondsLeft) = self else { return nil }
        let minutes = Int(secondsLeft / 60)
        return minutes >= 1
            ? String(localized: "Research time · \(minutes) min left")
            : String(localized: "Research time · under a minute left")
    }
}

/// The last seconds before an idle pause, surfaced so the app can ask
/// "still working?" instead of stopping silently.
///
/// The timing is the whole design: the warning occupies the FINAL stretch of
/// the existing idle tolerance, so an unanswered prompt pauses at exactly the
/// same moment the app pauses today. Confirming — or any input at all —
/// resets the idle clock and recording continues. Billing semantics are
/// untouched; the feature is a warning, not a new billing path.
struct IdleWarning: Equatable, Sendable {
    var secondsLeft: TimeInterval

    /// How long before the idle pause the warning appears (and therefore how
    /// long the user has to answer).
    static let lead: TimeInterval = 30

    /// Pure, so every branch is testable with plain values.
    static func evaluate(state: DetectionState, secondsSinceInput: TimeInterval,
                         idleThreshold: TimeInterval) -> IdleWarning? {
        // Only a running clock can warn about pausing; and a render that is
        // provably busy is already evidence of work — nagging during an
        // export would teach the user to ignore the prompt.
        guard state == .recording,
              idleThreshold > lead else { return nil }
        let remaining = idleThreshold - secondsSinceInput
        guard remaining > 0, remaining <= lead else { return nil }
        return IdleWarning(secondsLeft: remaining)
    }
}

/// A closed span of recorded work.
struct SessionRecord: Equatable, Sendable, Codable {
    var start: Date
    var end: Date
    var activeSeconds: TimeInterval
}

/// Accumulates active time across ticks. Pure value type — fully testable.
struct SessionAccumulator: Sendable {
    private(set) var sessionStart: Date?
    private(set) var activeSeconds: TimeInterval = 0

    mutating func tick(state: DetectionState, interval: TimeInterval, now: Date = Date()) {
        guard state == .recording else { return }
        if sessionStart == nil { sessionStart = now }
        activeSeconds += interval
    }

    /// Retroactive bridge credit: a short away-gap that ended with a return
    /// to the work context. Only meaningful while a session is open.
    mutating func credit(_ seconds: TimeInterval) {
        guard sessionStart != nil, seconds > 0 else { return }
        activeSeconds += seconds
    }

    mutating func endSession(at end: Date = Date()) -> SessionRecord? {
        guard let start = sessionStart else { return nil }
        let record = SessionRecord(start: start, end: end, activeSeconds: activeSeconds)
        sessionStart = nil
        activeSeconds = 0
        return record
    }
}
