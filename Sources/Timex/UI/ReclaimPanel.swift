import SwiftUI
import AppKit

/// The "away N min — add it?" card. Same manners as the idle warning: a
/// floating, non-activating panel that never steals focus from the work that
/// just resumed. The two panels can never appear together — the offer lapses
/// at 60s and the idle warning needs 90s of idle to open.
struct ReclaimView: View {
    let seconds: TimeInterval
    let accept: () -> Void
    let decline: () -> Void

    /// "14 min" / "1 h 20 min" — floored to the minute. Under-claiming the
    /// gap's size is on brand; over-claiming is not.
    static func gapText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    var body: some View {
        HStack(spacing: DT.s3) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(DT.body)
                .foregroundStyle(DT.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Away \(Self.gapText(seconds))")
                    .font(DT.bodyBold)
                    .foregroundStyle(DT.textPrimary)
                Text("Add it to this session? Unbilled unless you say so.")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.textSecondary)
            }
            Spacer(minLength: DT.s2)
            Button("No", action: decline)
                .buttonStyle(.plain)
                .font(DT.smallSemibold)
                .foregroundStyle(DT.textTertiary)
            Button("Add \(Self.gapText(seconds))", action: accept)
                .buttonStyle(.borderedProminent)
                .tint(DT.signal)
        }
        .padding(.horizontal, DT.s4)
        .padding(.vertical, DT.s3)
        .frame(width: 420)
        .background(DT.overlay, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.signal.opacity(0.45), lineWidth: 1))
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Away \(PillView.spokenDuration(seconds)). Add it to this session?")
    }
}

/// Same lifecycle pattern as IdleWarningController: driven from the engine's
/// existing tick, no timer of its own, pinnable for screenshots.
@MainActor
final class ReclaimController {
    private let model: AppModel
    private var panel: NSPanel?
    private var wasShowing = false
    private let pinnedForHarness: Bool

    init(model: AppModel) {
        self.model = model
        pinnedForHarness = ProcessInfo.processInfo.environment["TIMEX_SHOW"] == "reclaim"
        if pinnedForHarness {
            show(seconds: 14 * 60)
        }
    }

    func sync() {
        guard !ScenarioMode.isActive, !pinnedForHarness else { return }
        if let offer = model.engine.reclaimOffer {
            show(seconds: offer.seconds)
            if !wasShowing {
                model.announce("Away \(PillView.spokenDuration(offer.seconds)). "
                               + "Add it to this session?")
            }
            wasShowing = true
        } else {
            hide()
            wasShowing = false
        }
    }

    private func show(seconds: TimeInterval) {
        let view = ReclaimView(seconds: seconds,
                               accept: { [weak self] in self?.model.engine.acceptReclaim() },
                               decline: { [weak self] in self?.model.engine.declineReclaim() })
        if let panel {
            (panel.contentView as? NSHostingView<ReclaimView>)?.rootView = view
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
