import AppKit
import SwiftUI

/// Klokki-style colored pill in the menu bar. SwiftUI's MenuBarExtra label
/// renders template-only, so the pill lives in an NSStatusItem hosting a
/// SwiftUI view, with an NSPopover for the panel.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private var hostView: NSHostingView<PillView>?
    private var resizeTimer: Timer?

    private func syncWidth() {
        guard let host = hostView, let button = statusItem.button else { return }
        let w = host.fittingSize.width
        if abs(w - statusItem.length) > 0.5 {
            statusItem.length = w
            host.frame = NSRect(x: 0, y: 0, width: w, height: button.bounds.height)
        }
    }

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            // Frame-based sizing: autolayout constraints inside a status-bar
            // button blow the item up to screen width. Size the hosting view
            // from its fitting size and keep statusItem.length in sync.
            let host = NSHostingView(rootView: PillView(model: model))
            hostView = host
            let size = host.fittingSize
            host.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            statusItem.length = size.width
            button.addSubview(host)
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Cutaway")
            // No system highlight flash behind the custom pill — that gray
            // rounded "extension" on click was the button cell highlighting.
            (button.cell as? NSButtonCell)?.highlightsBy = []

            // Re-sync width once per second (session time appearing/growing
            // changes the pill's natural width).
            resizeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.syncWidth() }
            }
            // Width only changes when digit count changes — coalesce freely.
            resizeTimer?.tolerance = 0.5
        }

        popover.behavior = .transient
        popover.animates = true
        let panel = NSHostingController(rootView: MenuBarPanel(model: model))
        panel.view.frame.size = CGSize(width: 340, height: 380)
        popover.contentViewController = panel
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// The pill: [chip with mini ring][today total][session time].
struct PillView: View {
    @Bindable var model: AppModel

    private var isRecording: Bool { model.engine.state == .recording }
    private var goalReached: Bool { model.goalProgress.reached }
    private var accent: Color { goalReached ? DT.green : DT.orange }
    /// Traffic-light border: green = recording · amber = paused · red = no project.
    private var stateColor: Color {
        if model.selectedProject == nil { return DT.red }
        return isRecording ? DT.green : DT.amber
    }

    var body: some View {
        PillBody(stateColor: stateColor,
                 isRecording: isRecording,
                 showsPauseGlyph: model.selectedProject != nil && !isRecording,
                 goalFraction: model.goalProgress.fraction,
                 goalReached: goalReached,
                 seconds: model.pillSeconds,
                 bankedText: model.bankedFlash,
                 pausedHint: model.engine.pausedLong ? "‖ still paused" : nil)
            .accessibilityLabel(model.selectedProject == nil ? "No project selected"
                                : isRecording ? "Recording" : "Paused")
    }
}

/// Pure pill rendering — extracted from PillView so tests can render each
/// traffic-light state in isolation (no AppModel, no engine).
struct PillBody: View {
    let stateColor: Color
    let isRecording: Bool
    /// Paused WITH a project — pause bars in the ring. Shape encodes state
    /// redundantly with hue (deuteranopia collapses green/amber).
    let showsPauseGlyph: Bool
    let goalFraction: Double
    let goalReached: Bool
    let seconds: TimeInterval
    /// Transient session-banked confirmation — replaces the time readout.
    var bankedText: String? = nil
    /// Forgotten-pause hint (manual pause > 15 min) — amber, persistent.
    var pausedHint: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            // Bare state-colored circle — no chip background; the color IS
            // the state, matching the pill border.
            miniRing
                .frame(width: 18, height: 18)
            if let bankedText {
                Text(bankedText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DT.green)
            } else if let pausedHint {
                Text(pausedHint)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DT.amber)
            } else {
                Text(timeString(seconds))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(isRecording ? DT.text : DT.text2)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(stateColor.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(stateColor.opacity(0.6), lineWidth: 1)
        )
        .padding(.horizontal, 3)
    }

    private var miniRing: some View {
        ZStack {
            Circle()
                .stroke(goalReached ? stateColor : stateColor.opacity(0.25), lineWidth: 2.4)
            if !goalReached {
                Circle()
                    .trim(from: 0, to: max(goalFraction, 0.08))
                    .stroke(stateColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            // Shape-coded center: ● recording, ‖ paused, empty = no project.
            if isRecording {
                Circle().fill(stateColor).frame(width: 4.5, height: 4.5)
            } else if showsPauseGlyph {
                HStack(spacing: 1.6) {
                    Capsule().fill(stateColor).frame(width: 1.8, height: 6)
                    Capsule().fill(stateColor).frame(width: 1.8, height: 6)
                }
            }
        }
        .frame(width: 12, height: 12)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
