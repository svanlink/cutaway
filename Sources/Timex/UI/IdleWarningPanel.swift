import SwiftUI
import AppKit

/// The "still working?" card. Shown in a floating, NON-ACTIVATING panel —
/// stealing keyboard focus from Resolve to ask whether someone is working
/// would answer its own question in the worst possible way.
struct IdleWarningView: View {
    let secondsLeft: TimeInterval
    let confirm: () -> Void

    /// "Pauses in 12 s" — whole seconds, never negative, testable.
    static func countdownText(_ secondsLeft: TimeInterval) -> String {
        "Pauses in \(max(0, Int(secondsLeft.rounded()))) s"
    }

    var body: some View {
        HStack(spacing: DT.s3) {
            Image(systemName: "hourglass")
                .font(DT.body)
                .foregroundStyle(DT.held)
            VStack(alignment: .leading, spacing: 2) {
                Text("Still working?")
                    .font(DT.bodyBold)
                    .foregroundStyle(DT.textPrimary)
                Text("\(Self.countdownText(secondsLeft)) — any input keeps recording")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: DT.s2)
            Button("I'm still working", action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(DT.signal)
        }
        .padding(.horizontal, DT.s4)
        .padding(.vertical, DT.s3)
        .frame(width: 380)
        .background(DT.overlay, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.held.opacity(0.5), lineWidth: 1))
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Still working? \(Self.countdownText(secondsLeft))")
    }
}

/// Owns the panel's lifecycle. Driven from the engine's existing 1 Hz tick —
/// no timer of its own.
@MainActor
final class IdleWarningController {
    private let model: AppModel
    private var panel: NSPanel?
    private var wasShowing = false
    /// Harness hook: keep the panel up regardless of real idle state, so it
    /// can be screenshotted without waiting out 90 seconds of genuine idle.
    /// Without the pin, the first engine tick found no real warning and hid
    /// the panel again within a second of launch.
    private let pinnedForHarness: Bool

    init(model: AppModel) {
        self.model = model
        pinnedForHarness = ProcessInfo.processInfo.environment["TIMEX_SHOW"] == "idlewarning"
        if pinnedForHarness {
            show(secondsLeft: IdleWarning.lead)
        }
    }

    /// Called every engine tick.
    func sync() {
        guard !ScenarioMode.isActive, !pinnedForHarness else { return }
        if let warning = model.engine.idleWarning {
            show(secondsLeft: warning.secondsLeft)
            if !wasShowing {
                // Announced once at appearance — a per-second announcement
                // would be the pill-spam bug all over again.
                model.announce("Still working? The timer pauses in \(Int(IdleWarning.lead)) seconds.")
            }
            wasShowing = true
        } else {
            hide()
            wasShowing = false
        }
    }

    private func show(secondsLeft: TimeInterval) {
        let view = IdleWarningView(secondsLeft: secondsLeft) { [weak self] in
            self?.model.engine.confirmPresence()
        }
        if let panel {
            (panel.contentView as? NSHostingView<IdleWarningView>)?.rootView = view
            return
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let p = NSPanel(contentRect: host.frame,
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        p.contentView = host
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Top-right, under the menu bar — the neighbourhood the pill lives in.
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - host.frame.width - 16,
                                     y: f.maxY - host.frame.height - 12))
        }
        p.orderFrontRegardless()
        panel = p
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
