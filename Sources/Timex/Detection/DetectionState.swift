import Foundation

/// Why the timer is not recording.
enum PauseReason: String, Sendable, Codable {
    case manual
    case systemSleep
    case noProject
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
    /// ANCHOR apps (prefix-matched): the toolchain that proves a work block —
    /// they can START recording and refresh the research window.
    var workAppPrefixes: [String] = []
    /// SATELLITE apps (browsers, LLMs, mail, files): research/comms that
    /// SUSTAIN recording, but only while the research window is open.
    var satellitePrefixes: [String] = []
    /// True while within the research window of the last anchor activity —
    /// computed by the engine, consumed here.
    var satelliteWindowOpen: Bool = false
    /// True while an anchor app is provably burning cpu (a render/export) and
    /// the user has opted into billing that. Suppresses the idle pause ONLY —
    /// manual pause, sleep and leaving the work context still outrank it.
    var renderExemptionActive: Bool = false

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
        frontmostIsAnchor || (frontmostIsSatellite && satelliteWindowOpen)
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
        guard input.isWorkContext else { return .paused(.notFrontmost) }
        if input.secondsSinceInput >= input.idleThreshold, !input.renderExemptionActive {
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
            ? "Research time · \(minutes) min left"
            : "Research time · under a minute left"
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
                         idleThreshold: TimeInterval,
                         renderExemptionActive: Bool) -> IdleWarning? {
        // Only a running clock can warn about pausing; and a render that is
        // provably busy is already evidence of work — nagging during an
        // export would teach the user to ignore the prompt.
        guard state == .recording, !renderExemptionActive,
              idleThreshold > lead else { return nil }
        let remaining = idleThreshold - secondsSinceInput
        guard remaining > 0, remaining <= lead else { return nil }
        return IdleWarning(secondsLeft: remaining)
    }
}

/// An automatic pause the user might want their time back from.
///
/// The bridge auto-credits detours under the grace period; beyond it, away
/// time was simply gone even when it was billable — a client call about the
/// cut, reference footage on another machine. This offers it back ONCE, on
/// return, and the defaults all point the honest way: default No, timing out
/// to No, never offered for a manual pause or system sleep (those boundaries
/// are sacred), and nothing is billed unless the user explicitly says so.
struct ReclaimOffer: Equatable, Sendable {
    var start: Date
    var end: Date
    var seconds: TimeInterval { end.timeIntervalSince(start) }

    /// How long the offer stays open before it answers itself with No.
    /// Deliberately shorter than the idle warning's 90s trigger, so the two
    /// cards can never be on screen at once.
    static let duration: TimeInterval = 60
    /// Above this, a gap is not a detour — it is a break or the end of the
    /// day, and a one-click "add 3 hours" is an invoice mistake waiting for
    /// a fat finger.
    static let maximumGap: TimeInterval = 2 * 3600
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
