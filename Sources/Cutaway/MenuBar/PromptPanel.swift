import SwiftUI
import AppKit

enum Prompt: Equatable {
    case idle(secondsLeft: TimeInterval)
    case resume
    /// A name nobody has claimed yet.
    case attribution(name: String, source: AttributionPolicy.Source, current: String?)
}

/// Which floating card, if any. Pure.
///
/// Three kinds now, and the invariant is unchanged: never two at once. The
/// third earns its place by replacing a silent wrong guess rather than adding
/// a new interruption — it only appears for a name the app has never been
/// told about, and it is asked once per name, ever.
///
/// Order matters. A question about attribution can wait; a timer about to
/// pause cannot, and a pause the owner is working through is costing money
/// right now.
enum PromptArbiter {
    static func visible(idle: IdleWarning?, resumeAsked: Bool,
                        manuallyPaused: Bool, state: DetectionState,
                        attribution: (name: String, source: AttributionPolicy.Source, current: String?)? = nil) -> Prompt? {
        if manuallyPaused { return resumeAsked ? .resume : nil }
        if state == .recording, let idle { return .idle(secondsLeft: idle.secondsLeft) }
        if let a = attribution {
            return .attribution(name: a.name, source: a.source, current: a.current)
        }
        return nil
    }
}

/// The one shape both prompts take: leading glyph, title, one line, actions.
struct PromptCard<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let line: LocalizedStringKey
    let spoken: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: DT.s3) {
            Image(systemName: symbol).font(DT.body).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DT.bodyBold).foregroundStyle(DT.textPrimary)
                Text(line).font(DT.captionMedium).foregroundStyle(DT.textSecondary).monospacedDigit()
            }
            Spacer(minLength: DT.s2)
            actions()
        }
        .padding(.horizontal, DT.s4)
        .padding(.vertical, DT.s3)
        .frame(width: 400)
        .background(DT.overlay, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(tint.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken)
    }
}

/// "Are you working?" — the ask-mode reply to anchor activity during a
/// manual pause. Yes resumes; No stays paused (the engine's cooldown keeps
/// it from asking again for 15 minutes).
struct ResumePromptView: View {
    let resume: () -> Void
    let stay: () -> Void
    /// Resume, and stop asking. This was a Settings picker ("After a manual
    /// pause: stay paused / ask me / resume automatically") that nobody ever
    /// touched. The decision belongs here, where the question is live and the
    /// answer is obvious — not in a window opened once a year.
    let always: () -> Void

    var body: some View {
        PromptCard(symbol: "play.circle", tint: DT.signal, title: "Are you working?",
                   line: "Cutaway is paused, but you're editing.",
                   spoken: String(localized: "Are you working? Cutaway is paused, but you're editing.")) {
            Button("No, stay paused", action: stay)
                .buttonStyle(.plain).font(DT.smallSemibold).foregroundStyle(DT.textTertiary)
            Button("Always", action: always)
                .buttonStyle(.plain).font(DT.smallSemibold).foregroundStyle(DT.textTertiary)
                .accessibilityLabel("Always resume automatically")
                .help("Resume now, and from now on resume without asking")
            Button("Yes, resume", action: resume)
                .buttonStyle(.borderedProminent).tint(DT.signal)
        }
    }
}

/// Where a newly seen name belongs. Three answers, and each one is
/// remembered: the app asks about a given name exactly once.
struct AttributionPromptView: View {
    let name: String
    let source: AttributionPolicy.Source
    let current: String?
    let attach: () -> Void
    let create: () -> Void
    let ignore: () -> Void

    var body: some View {
        let q = AttributionPolicy.question(name: name, source: source, current: current)
        return PromptCard(symbol: source.isDocument ? "doc.badge.plus" : "film.stack",
                          tint: DT.signal,
                          title: LocalizedStringKey(q.title),
                          line: LocalizedStringKey(q.line),
                          spoken: "\(q.title). \(q.line)") {
            Button("Not billable", action: ignore)
                .buttonStyle(.plain).font(DT.smallSemibold).foregroundStyle(DT.textTertiary)
            Button("New project", action: create)
                .buttonStyle(.plain).font(DT.smallSemibold).foregroundStyle(DT.text2)
            if current != nil {
                // The common answer for an Adobe document: same job, other app.
                Button("Yes", action: attach)
                    .buttonStyle(.borderedProminent).tint(DT.signal)
            }
        }
    }
}

/// The single floating, NON-ACTIVATING panel the prompts share — stealing
/// keyboard focus from Resolve to ask whether someone is working would
/// answer its own question in the worst possible way. Driven from the
/// engine's 1 Hz tick; no timer of its own.
@MainActor
final class PromptPanel {
    private let model: AppModel
    private var panel: NSPanel?
    private var showing: Prompt?
    /// Harness hook: CUTAWAY_SHOW=idlewarning|resume pins a card for screenshots.
    private let pinned: Prompt?

    init(model: AppModel) {
        self.model = model
        switch ProcessInfo.processInfo.environment["CUTAWAY_SHOW"] {
        case "idlewarning": pinned = .idle(secondsLeft: IdleWarning.lead)
        case "resume": pinned = .resume
        default: pinned = nil
        }
        if let pinned { show(pinned) }
    }

    func sync() {
        guard !ScenarioMode.isActive, pinned == nil else { return }
        let next = PromptArbiter.visible(idle: model.engine.idleWarning,
                                         resumeAsked: model.resumePromptOpen,
                                         manuallyPaused: model.engine.manuallyPaused,
                                         state: model.engine.state,
                                         attribution: model.pendingAttribution)
        guard let next else { hide(); return }
        let isNew = !sameKind(showing, next)
        show(next)
        if isNew {
            // Announced once at appearance — per-second would be the
            // pill-spam bug all over again.
            switch next {
            case .idle: model.announce(String(localized: "Still working? The timer pauses in \(Int(IdleWarning.lead)) seconds."))
            case .resume: model.announce(String(localized: "Are you working? Cutaway is paused, but you're editing."))
            case .attribution(let name, let source, let current):
                let q = AttributionPolicy.question(name: name, source: source, current: current)
                model.announce("\(q.title). \(q.line)")
            }
        }
    }

    private func sameKind(_ a: Prompt?, _ b: Prompt) -> Bool {
        switch (a, b) {
        case (.idle, .idle), (.resume, .resume): return true
        default: return false
        }
    }

    private func view(for prompt: Prompt) -> AnyView {
        switch prompt {
        case .idle(let left):
            return AnyView(IdleWarningView(secondsLeft: left) { [weak self] in
                self?.model.engine.confirmPresence()
            })
        case .attribution(let name, let source, let current):
            return AnyView(AttributionPromptView(
                name: name, source: source, current: current,
                attach: { [weak self] in self?.model.attachDetectedName(name) },
                create: { [weak self] in self?.model.createProjectForDetectedName(name) },
                ignore: { [weak self] in self?.model.ignoreDetectedName(name) }))
        case .resume:
            return AnyView(ResumePromptView(
                resume: { [weak self] in self?.model.engine.resume(); self?.model.resumePromptOpen = false },
                stay: { [weak self] in self?.model.resumePromptOpen = false },
                always: { [weak self] in
                    guard let self else { return }
                    Prefs.set(AutoResumeMode.auto.rawValue, forKey: "autoResume")
                    self.model.engine.autoResume = .auto
                    self.model.engine.resume()
                    self.model.resumePromptOpen = false
                }))
        }
    }

    private func show(_ prompt: Prompt) {
        showing = prompt
        let v = view(for: prompt)
        if let panel {
            (panel.contentView as? NSHostingView<AnyView>)?.rootView = v
            return
        }
        let host = NSHostingView(rootView: v)
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
        showing = nil
    }
}
