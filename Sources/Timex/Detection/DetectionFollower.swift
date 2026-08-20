import Foundation

/// Project-name comparison, in one place. Tiers disagree about case,
/// whitespace and diacritics, and two spellings of one project silently
/// split its billing.
enum ProjectName {
    static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func matches(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }
}

/// Auto-switch follows CHANGES in what Resolve reports — not its steady
/// state.
///
/// The distinction is the whole point. Acting on steady state means a poll
/// every five seconds re-asserts whatever Resolve has loaded, so a manual
/// switch survives at most five seconds and an editor working in After
/// Effects for one project, with another open in Resolve, bills to the wrong
/// one. Acting on transitions means Resolve moving is what moves attribution,
/// and the user's explicit choice stands until it does.
struct DetectionFollower {
    private(set) var lastSeen: String?

    /// The project to switch to, or nil when Resolve has not moved.
    /// The FIRST observation is always a transition — that is how a fresh
    /// install adopts whatever is already open.
    mutating func observe(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        defer { lastSeen = name }
        guard let last = lastSeen else { return name }
        return ProjectName.matches(last, name) ? nil : name
    }

    /// Resolve quit, or stopped reporting. The next name it gives is a fresh
    /// transition rather than a continuation of what it said before it went.
    mutating func reset() {
        lastSeen = nil
    }
}

/// Explicit user choices, counted.
///
/// Tier 1 spawns fuscript and answers seconds later. Without this, an answer
/// that started before the user picked a project lands on top of that pick —
/// the same automation-beats-intent defect as steady-state switching, but
/// racy, so it reads as "the app randomly changed my project".
///
/// A detection carries the count from when it STARTED. If the count has moved
/// by the time it answers, the user chose in the meantime and the answer
/// describes a world they have already left.
struct ManualIntent {
    typealias Token = Int
    private(set) var token: Token = 0

    mutating func userChose() {
        token += 1
    }

    func hasMovedSince(_ started: Token) -> Bool {
        started != token
    }
}

/// Where a manual pause is remembered across runs.
///
/// Kept beside the engine rather than inside it so the keys, the restore
/// rule and the "a start without a pause is not a pause" guard all live in
/// one readable place — a half-restored pause is worse than none.
enum PauseState {
    static let pausedKey = "manuallyPaused"
    static let startKey = "manualPauseStart"

    /// Only a start that belongs to an actual pause is restored.
    static func restoredStart(from defaults: UserDefaults = Prefs) -> Date? {
        guard defaults.bool(forKey: pausedKey) else { return nil }
        let stamp = defaults.double(forKey: startKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    static func persist(start: Date?, to defaults: UserDefaults = Prefs) {
        if let start {
            defaults.set(start.timeIntervalSince1970, forKey: startKey)
        } else {
            defaults.removeObject(forKey: startKey)
        }
    }
}
