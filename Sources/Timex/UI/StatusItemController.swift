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
    /// Last value handed to VoiceOver, so an unchanged one is not re-announced.
    private var lastSpokenValue = ""
    /// Live only while the panel is open.
    private var escapeMonitor: Any?

    /// VoiceOver re-speaks a focused element when its label changes. Writing
    /// this every second meant the pill recited itself once a second, forever,
    /// while focused — and `spokenDuration` has MINUTE resolution, so 59 of
    /// every 60 writes were byte-identical. All cost, no information.
    ///
    /// It is also the VALUE, not the name: the name is "Cutaway" and does not
    /// change; the figure does.
    private func syncAccessibilityLabel() {
        let spoken = PillView.accessibilityLabel(
            project: model.selectedProject?.name,
            isRecording: model.engine.state == .recording,
            seconds: model.pillSeconds,
            banked: model.bankedFlash,
            pausedHint: model.engine.pausedLong ? "still paused" : nil)
        guard spoken != lastSpokenValue else { return }
        lastSpokenValue = spoken
        statusItem.button?.setAccessibilityValue(spoken)
    }

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
            // The pill is announced by the BUTTON. Left as an element, the
            // hosting view appears as a child saying the identical thing.
            host.setAccessibilityElement(false)
            button.addSubview(host)
            button.target = self
            button.action = #selector(statusItemClicked)
            // Right-click and Ctrl-click open a real menu. Apple's HIG says a
            // menu bar extra must offer Quit; this app had none anywhere, and
            // in accessory mode there is no app menu bar either — so a user
            // who closed the window could not quit Cutaway without Activity
            // Monitor.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // The name is set once and never changes; the figure travels as
            // the accessibility VALUE instead.
            button.setAccessibilityLabel("Cutaway")
            syncAccessibilityLabel()
            // No system highlight flash behind the custom pill — that gray
            // rounded "extension" on click was the button cell highlighting.
            (button.cell as? NSButtonCell)?.highlightsBy = []

            // The pill's width changes when the session time gains a digit,
            // and its label changes with the time. Both ride the engine's
            // existing 1 Hz tick: a second timer running for the life of the
            // app — while paused, backgrounded, and showing a static number,
            // on a machine that is rendering video — bought nothing.
            model.onEngineTick = { [weak self] in
                self?.syncWidth()
                self?.syncAccessibilityLabel()
            }
        }

        popover.behavior = .transient
        // The popover's scale-in is the largest movement this app makes, it
        // fires dozens of times a day, and it happens in peripheral vision
        // next to the menu bar.
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let panel = NSHostingController(rootView: MenuBarPanel(model: model))
        panel.view.frame.size = CGSize(width: 340, height: 380)
        popover.contentViewController = panel
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        wantsMenu ? showMenu() : togglePopover()
    }

    /// Built fresh each time so the first item reflects the current state.
    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Cutaway", action: #selector(openMain), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: model.engine.manuallyPaused ? "Resume" : "Pause",
                     action: #selector(togglePause), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cutaway", action: #selector(quit), keyEquivalent: "q")
            .target = self
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    /// Keys the panel answers while it is open.
    ///
    /// Escape, because a panel you can open with the keyboard and not close
    /// with it is a trap (WCAG 2.1.2). A local monitor rather than
    /// .onExitCommand: that depends on the SwiftUI responder chain reaching a
    /// view hosted inside an NSPopover, and it only manages it about two
    /// times in three.
    ///
    /// Cmd-Q, because the right-click menu that offers Quit cannot be reached
    /// from a keyboard — right-click never can. The keyboard route into this
    /// app is Ctrl-F8 then Return, which lands here, so this is where the
    /// universal quit shortcut has to work. It costs no visible chrome, which
    /// is why it beats a button in the footer.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {                                   // Escape
                self?.closePopover()
                return nil
            }
            if event.charactersIgnoringModifiers?.lowercased() == "q",
               event.modifierFlags.contains(.command) {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        NSApp.setAccessibilityChildren(nil)
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        // Focus goes back where it came from, so Escape does not strand the
        // keyboard user somewhere they did not navigate to.
        statusItem.button?.window?.makeKey()
    }

    @objc private func openMain() { model.openMainWindow?() }
    @objc private func openSettings() { model.openSettingsWindow?() }
    @objc private func togglePause() { model.engine.togglePause() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            // Without this the panel's contents are absent from the
            // accessibility tree entirely — VoiceOver and XCUITest both see an
            // empty popover.
            if let content = popover.contentViewController?.view {
                NSApp.setAccessibilityChildren([content])
            }
            installEscapeMonitor()
        }
    }
}

/// The pill: [chip with mini ring][today total][session time].
struct PillView: View {
    @Bindable var model: AppModel

    private var isRecording: Bool { model.engine.state == .recording }
    private var goalReached: Bool { model.goalProgress.reached }
    private var accent: Color { goalReached ? DT.signal : DT.recording }
    /// Traffic-light border: green = recording · amber = paused · red = no project.
    private var stateColor: Color {
        if model.selectedProject == nil { return DT.barRed }
        return isRecording ? DT.barGreen : DT.barAmber
    }

    /// What the pill says to VoiceOver. It used to say only the state —
    /// "Recording" — while the number the whole app exists to show, and the
    /// project it belongs to, were visible to everyone else and to nobody
    /// using a screen reader.
    static func accessibilityLabel(project: String?, isRecording: Bool,
                                   seconds: TimeInterval, banked: String?,
                                   pausedHint: String?) -> String {
        guard let project, !project.isEmpty else { return "Cutaway — no project selected" }
        // The flash and the hint REPLACE the readout on screen, so they
        // replace it here too: announcing a time that is not being shown
        // would describe a pill that does not exist.
        if let banked {
            return "Cutaway — \(banked.replacingOccurrences(of: "✓ ", with: "")), \(project)"
        }
        if pausedHint != nil {
            return "Cutaway — still paused, \(project)"
        }
        return "Cutaway — \(isRecording ? "recording" : "paused"), "
            + "\(spokenDuration(seconds)), \(project)"
    }

    /// "2 hours 14 minutes", not "2:14:07" — a screen reader spelling out a
    /// clock string is a worse experience than no clock string.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 && minutes == 0 { return "under a minute" }
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
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
            .accessibilityLabel(Self.accessibilityLabel(
                project: model.selectedProject?.name,
                isRecording: isRecording,
                seconds: model.pillSeconds,
                banked: model.bankedFlash,
                pausedHint: model.engine.pausedLong ? "still paused" : nil))
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
                    .font(DT.pillMessage)
                    .foregroundStyle(DT.barGreen)
            } else if let pausedHint {
                Text(pausedHint)
                    .font(DT.pillMessage)
                    .foregroundStyle(DT.barAmber)
            } else {
                Text(timeString(seconds))
                    .font(DT.pillTime)
                    .foregroundStyle(isRecording ? DT.barText : DT.barText2)
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
