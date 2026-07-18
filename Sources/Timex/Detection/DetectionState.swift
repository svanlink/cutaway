import Foundation

/// Why the timer is not recording.
enum PauseReason: String, Sendable, Codable {
    case manual
    case systemSleep
    case noProject
    case notFrontmost
    case inputIdle
}

enum DetectionState: Equatable, Sendable {
    case recording
    case paused(PauseReason)
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

    /// Resolve ships under one bundle id, but keep this a set so App Store /
    /// regional variants can be added without touching logic.
    static let resolveBundleIDs: [String] = [
        "com.blackmagic-design.DaVinciResolve",
        "com.blackmagic-design.DaVinciResolveLite",
        "com.blackmagic-design.DaVinciResolveStudio",
    ]

    /// Adobe bundle ids carry year suffixes (com.adobe.PremierePro.2025) —
    /// prefix matching covers all versions.
    static let defaultWorkAppPrefixes: [String] = [
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

    var frontmostIsAnchor: Bool {
        guard let front = frontmostBundleID else { return false }
        if Self.resolveBundleIDs.contains(front) { return true }
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
        if input.secondsSinceInput >= input.idleThreshold { return .paused(.inputIdle) }
        return .recording
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
