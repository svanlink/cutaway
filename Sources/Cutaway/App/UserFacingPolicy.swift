import Foundation

/// The decisions the app makes about what to SAY to the user, separated from
/// the object that happens to have the data to answer them.
///
/// These lived as static functions on AppModel, which is what kept happening
/// every time a policy was added: the logic wants to be a pure function of a
/// small typed input, and a `static` keyword was the nearest way to say so.
/// They sit here for the same reason `DetectionState.evaluate` sits beside
/// the state machine it decides for.
enum ZeroStatePolicy {
/// Why the timer has nothing to show. The app's own answer to the
/// question a first-run user actually asks — "why isn't this counting?"
/// — which until now lived only in the README.
enum ZeroState: Equatable {
    /// Nothing exists to attribute time to.
    case noProject
    /// A project exists but has never been tracked against.
    case nothingTrackedYet(resolveRunning: Bool)
}

/// Pure so every branch is testable without standing up a store.
/// nil means the app has what it needs — say nothing.
static func zeroState(hasProject: Bool, trackedSeconds: TimeInterval,
                      isRecording: Bool, resolveRunning: Bool) -> ZeroState? {
    guard hasProject else { return .noProject }
    // Recorded history (or a running clock) means this is not a zero
    // state — a quiet afternoon is not the same as an empty app.
    guard trackedSeconds <= 0, !isRecording else { return nil }
    return .nothingTrackedYet(resolveRunning: resolveRunning)
}

static func zeroStateTitle(_ state: ZeroState) -> String {
    switch state {
    case .noProject: return "No project yet"
    case .nothingTrackedYet: return "Nothing tracked yet"
    }
}

/// Says what starts the clock, in the user's actual situation. Never
/// promises detection that cannot happen — with Resolve closed, working
/// in a workflow app is the honest instruction.
static func zeroStateHint(_ state: ZeroState) -> String {
    switch state {
    case .noProject:
        return "Create one and Cutaway starts tracking against it. Open a project in Resolve and it makes one for you."
    case .nothingTrackedYet(let resolveRunning):
        return resolveRunning
            ? "Resolve is open. Start editing — the clock starts by itself and stops when you do."
            : "Open your project in Resolve, or just start working in one of your workflow apps. The clock starts by itself."
    }
}
}

/// When to offer Accessibility permission, and when to leave the user alone.
enum AccessibilityOfferPolicy {
/// Accessibility is the difference between instant project switching and
/// a 30–120s scripting poll, and it used to be discoverable only by
/// wandering into Settings. Offer it ONCE, in context — never before
/// there is a project to detect for, never when it is already granted,
/// never again after a decline, and never stacked on top of a zero state
/// that is already asking for the user's attention.
static func shouldOfferAccessibility(granted: Bool, dismissed: Bool, hasProject: Bool,
                                     zeroStateShowing: Bool = false) -> Bool {
    guard hasProject, !granted, !dismissed, !zeroStateShowing else { return false }
    return true
}
}

/// The first-run primer: shown once, never during a verification run.
enum PermissionsPrimerPolicy {
    static func shouldShow(alreadyShown: Bool, scenario: Bool) -> Bool { !alreadyShown && !scenario }
    static var statement: String { String(localized: "Cutaway never asks for Screen Recording, never reads keystrokes, and nothing leaves your Mac.") }
}
