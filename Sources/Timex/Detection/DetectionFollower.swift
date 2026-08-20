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
