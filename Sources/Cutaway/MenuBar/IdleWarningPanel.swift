import SwiftUI

/// The "still working?" card — the final stretch of the idle tolerance,
/// surfaced so the app asks instead of stopping silently. Hosted by
/// PromptPanel; billing semantics untouched.
struct IdleWarningView: View {
    let secondsLeft: TimeInterval
    let confirm: () -> Void

    /// "Pauses in 12 s" — whole seconds, never negative, testable.
    static func countdownText(_ secondsLeft: TimeInterval) -> String {
        "Pauses in \(max(0, Int(secondsLeft.rounded()))) s"
    }

    var body: some View {
        PromptCard(symbol: "hourglass", tint: DT.held, title: "Still working?",
                   line: "\(Self.countdownText(secondsLeft)) — any input keeps recording",
                   spoken: "Still working? \(Self.countdownText(secondsLeft))") {
            Button("I'm still working", action: confirm)
                .buttonStyle(.borderedProminent).tint(DT.signal)
        }
    }
}
