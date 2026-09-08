import SwiftUI
import AppKit

enum PanelBlock: Hashable {
    case hero, storeProblem, zeroState, accessibilityOffer, projects, resumeBanner, researchWindow, receipt, footer
}

/// The Klokki-inspired drop-down: hero header, project list, footer bar.
/// The pill and this panel ARE the app; the Stats window is for sitting down.
struct MenuBarPanel: View {
    @Bindable var model: AppModel
    /// With Reduce Transparency on, a material over the desktop is exactly
    /// what the user asked the system not to do — and it is the only reason
    /// this panel's contrast cannot be computed, since it depends on whatever
    /// wallpaper happens to be behind it.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The pause control's state change is the one animation the panel
    /// makes; Reduce Motion turns it into a cut.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { model.engine.state == .recording }
    private var accent: Color { DT.recording }

    /// Pure: what the panel shows, in order. With no project there is
    /// nothing to list, so the zero state takes the list's place.
    static func blocks(zeroState: Bool, offersAccessibility: Bool,
                       workDetectedWhilePaused: Bool, researchLabel: Bool,
                       receipt: Bool, storeProblem: Bool = false,
                       projectMismatch: Bool = false) -> [PanelBlock] {
        var b: [PanelBlock] = [.hero]
        // A failed save outranks everything: it is the one line that can
        // save the user money if they read it.
        if storeProblem { b.append(.storeProblem) }
        if zeroState { return b + [.zeroState, .footer] }
        if offersAccessibility { b.append(.accessibilityOffer) }
        b.append(.projects)
        // A held clock outranks the research line: while it is true, the
        // only question worth answering is why nothing is counting.
        if workDetectedWhilePaused || projectMismatch { b.append(.resumeBanner) }
        if researchLabel { b.append(.researchWindow) }
        if receipt { b.append(.receipt) }
        b.append(.footer)
        return b
    }

    var body: some View {
        let blocks = Self.blocks(zeroState: model.zeroState != nil,
                                 offersAccessibility: model.shouldOfferAccessibility,
                                 workDetectedWhilePaused: model.engine.workDetectedWhilePaused,
                                 researchLabel: model.engine.recordingSource?.label != nil,
                                 receipt: model.lastSessionLine != nil || model.unbilledLine != nil,
                                 storeProblem: model.storeErrors.banner != nil,
                                 projectMismatch: model.projectMismatch)
        VStack(spacing: 0) {
            ForEach(blocks, id: \.self) { block in
                switch block {
                case .hero: hero
                case .storeProblem:
                    Text(model.storeErrors.banner ?? "")
                        .font(DT.captionMedium)
                        .foregroundStyle(DT.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DT.rowInset).padding(.vertical, DT.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DT.alarm.opacity(0.25))
                        .contentShape(Rectangle())
                        .onTapGesture { model.storeErrors.clear() }   // a fatal one stays
                        .accessibilityLabel(model.storeErrors.banner ?? "")
                case .zeroState:
                    ZeroStateCard(state: model.zeroState ?? .noProject) {
                        model.showNewProjectSheet = true
                        model.openMainWindow?()
                    }
                case .accessibilityOffer:
                    AccessibilityOfferCard(enable: { model.detector.requestAccessibility() },
                                           dismiss: { model.accessibilityOfferDismissed = true })
                case .projects: projectList
                case .resumeBanner:
                    resumeBanner
                    mismatchBanner
                case .researchWindow: researchWindow
                case .receipt: receipt
                case .footer: footer
                }
            }
        }
        .frame(width: 340)
        // Escape is handled by the controller with a key monitor, not here:
        // .onExitCommand depends on the SwiftUI responder chain reaching a
        // view hosted inside an NSPopover, which it does only sometimes — a
        // dismissal that works two runs in three is a keyboard trap.
        .accessibilityAddTraits(.isModal)
        .background(reduceTransparency ? AnyShapeStyle(DT.overlay) : AnyShapeStyle(.ultraThinMaterial))
        .background(reduceTransparency ? DT.overlay : DT.window.opacity(0.55))
    }

    // MARK: - Hero

    /// The hero doubles as the way back into the app — click anywhere on
    /// it to open the Stats window (stupid-proof reentry).
    private var hero: some View {
        Button {
            model.openMainWindow?()
        } label: {
            HStack(spacing: 0) {
                ZStack {
                    Color.black
                    heroRing
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 1) {
                    elapsedText
                    Text(model.todayMoney)
                        .font(DT.moneyFont)
                        .foregroundStyle(isRecording ? DT.money : DT.textSecondary)
                        .monospacedDigit()
                    Text(model.selectedProject?.client.isEmpty == false
                         ? model.selectedProject!.client.uppercased()
                         : "CUTAWAY")
                        .font(DT.panelClient)
                        .kerning(0.84)
                        .foregroundStyle(isRecording ? accent : DT.text3)
                        .padding(.top, 3)
                    Text(model.selectedProject?.name ?? "No project")
                        .font(DT.panelProject)
                        .foregroundStyle(DT.text)
                        .lineLimit(1)
                    .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(isRecording ? accent.opacity(0.12) : Color.white.opacity(0.04))
            }
            .frame(height: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Was "Open Cutaway", which discarded the elapsed time, the client and
        // the project — the largest number on screen did not exist.
        .accessibilityLabel(heroLabel)
        .accessibilityHint("Open Cutaway")
        .help("Open Cutaway")
    }

    private var heroLabel: String {
        let worked = PillView.spokenDuration(model.todaySeconds)
        guard let project = model.selectedProject else { return "Today \(worked), no project" }
        let client = project.client.isEmpty ? "" : ", \(project.client)"
        return "Today \(worked), \(model.todayMoney), \(project.name)\(client)"
    }

    private var heroRing: some View {
        Circle()
            .stroke(isRecording ? accent : DT.ringPaused, lineWidth: 7)
            .frame(width: 52, height: 52)
    }

    private var elapsedText: some View {
        let s = Int(model.todaySeconds)
        let main = String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
        let sec = String(format: ":%02d", s % 60)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(main).font(DT.panelHero).foregroundStyle(DT.text)
            Text(sec).font(DT.panelHeroSeconds).foregroundStyle(DT.text2)
        }
        .monospacedDigit()
    }

    // MARK: - Project list

    private var projectList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.projects, id: \.persistentModelID) { p in
                    PanelRow(
                        project: p,
                        isRunning: p.persistentModelID == model.selectedProjectID && isRecording,
                        isSelected: p.persistentModelID == model.selectedProjectID,
                        todaySeconds: model.todaySecondsFor(p),
                        sessionSeconds: model.engine.accumulator.activeSeconds,
                        installed: model.installedApps
                    ) {
                        model.selectManually(p)
                    }
                    .contextMenu {
                        Button("Edit project…") {
                            model.editTarget = p
                            model.openMainWindow?()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 176)
    }

    // MARK: - Research window

    /// The clock is held because Resolve is on something else. A stopped
    /// timer with no explanation is indistinguishable from a broken one.
    @ViewBuilder
    private var mismatchBanner: some View {
        if model.projectMismatch, let onScreen = model.resolveProject {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DT.glyph)
                VStack(alignment: .leading, spacing: 1) {
                    (model.heldNameIsIgnored
                        ? Text("Not recording — you marked this project not billable")
                        : Text("Not recording — Resolve is on another project"))
                        .font(DT.smallSemibold)
                    Text(onScreen)
                        .font(DT.captionMedium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                // A hold with no way out is a trap. This is the door.
                Button {
                    model.reconsiderIgnoredName()
                    model.raiseAttributionIfHeld()
                } label: {
                    // Two Texts, not a ternary of literals: a ternary
                    // resolves to String, which is verbatim and never reaches
                    // the catalog. Third time this trap has been hit.
                    model.heldNameIsIgnored ? Text("Bill it after all") : Text("Choose…")
                }
                .buttonStyle(DayActionButtonStyle())
                .fixedSize()
            }
            .foregroundStyle(DT.held)
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DT.held.opacity(0.12))
            .overlay(alignment: .top) { Rectangle().fill(DT.strokeSubtle).frame(height: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Not recording. Resolve is on \(onScreen), which is not the selected project.")
        }
    }

    /// Only shown while a satellite app is holding the clock up. Recording
    /// from Resolve needs no explanation — it stops when the work does. This
    /// one stops on a timer the user cannot otherwise see.
    @ViewBuilder
    private var researchWindow: some View {
        if let label = model.engine.recordingSource?.label {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(DT.glyph)
                Text(label)
                    .font(DT.captionMedium)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(model.researchWindowIsClosing ? DT.held : DT.textTertiary)
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.researchWindowIsClosing ? DT.held.opacity(0.12) : Color.clear)
            .overlay(alignment: .top) {
                Rectangle().fill(DT.strokeSubtle).frame(height: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
        }
    }

    // MARK: - Resume banner

    /// Paused by hand, but Resolve is clearly being driven. The notification
    /// asks the same question; this is the answer that needs no permission.
    @ViewBuilder
    private var resumeBanner: some View {
        if model.engine.workDetectedWhilePaused {
            HStack(spacing: DT.s2) {
                Text("Looks like you're working")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.amber)
                Spacer(minLength: 0)
                Button {
                    model.engine.resume()
                    model.resumePromptOpen = false
                } label: {
                    Text("Resume")
                        .font(DT.smallSemibold)
                        .foregroundStyle(DT.onSignal)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(DT.signal, in: RoundedRectangle(cornerRadius: DT.rSm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume tracking")
            }
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s2)
            .background(DT.amber.opacity(0.08))
            .overlay(alignment: .top) {
                Rectangle().fill(DT.strokeSubtle).frame(height: 1)
            }
        }
    }

    // MARK: - Receipt

    /// The last banked session, stated plainly and permanently. The pill's
    /// 4s flash is the celebration; this is the proof that outlives it.
    @ViewBuilder
    private var receipt: some View {
        if let line = model.lastSessionLine {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(DT.glyph)
                Text(line)
                    .font(DT.captionMedium)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DT.text3)
            .padding(.horizontal, DT.rowInset)
            .padding(.vertical, DT.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(DT.strokeSubtle).frame(height: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(line)
        }
        // Money worked and not yet on an invoice. It rides the receipt block
        // rather than taking a block of its own — the panel interrupts for
        // two things and shows one number; this is a quiet second line under
        // an existing one, not a third surface.
        if let unbilled = model.unbilledLine {
            HStack(spacing: 6) {
                Image(systemName: "tray.full").font(DT.glyph)
                Text("\(unbilled) unbilled")
                    .font(DT.captionMedium).monospacedDigit().lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DT.text3)
            .padding(.horizontal, DT.rowInset)
            .padding(.bottom, DT.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(unbilled) not yet invoiced")
        }
    }

    // MARK: - Footer

    /// The app's primary control, on the surface that is open all day.
    private var pauseButton: some View {
        let paused = model.engine.manuallyPaused
        return Button { model.engine.togglePause() } label: {
            HStack(spacing: DT.s1) {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(DT.buttonGlyph)
                Text(paused ? "Resume" : "Pause").font(DT.smallSemibold)
            }
            .foregroundStyle(paused ? DT.text : DT.onSignal)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(paused ? AnyShapeStyle(Color.white.opacity(0.12)) : AnyShapeStyle(DT.signal),
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: paused)
        .disabled(model.selectedProject == nil)
        .accessibilityLabel(paused ? Text("Resume timer") : Text("Pause timer"))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            pauseButton
            footBtn("＋", help: "New Project") {
                model.showNewProjectSheet = true
                model.openMainWindow?()
            }
            Button { model.openMainWindow?() } label: {
                Text("Stats ↗")
                    .font(DT.smallSemibold)
                    .foregroundStyle(DT.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            footBtn("⚙", help: "Settings") {
                // showSettingsWindow: was removed in macOS 14 — the old
                // silent-no-op bug. Settings is a real window we open.
                model.openSettingsWindow?()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.35))
    }

    private func footBtn(_ label: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DT.smallSemibold)
                .foregroundStyle(DT.text2)
                .frame(width: 32, height: 26)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
    }
}

private struct PanelRow: View {
    let project: Project
    let isRunning: Bool
    let isSelected: Bool
    let todaySeconds: TimeInterval
    let sessionSeconds: TimeInterval
    let installed: [InstalledApp]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isRunning ? AnyShapeStyle(DT.recording) : AnyShapeStyle(Color.white.opacity(0.08)))
                    if isRunning {
                        Circle()
                            .trim(from: 0, to: 0.75)
                            .stroke(DT.onSignal, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "play.fill")
                            .font(DT.glyphTiny)
                            .foregroundStyle(DT.text3)
                    }
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(isRunning ? DT.panelRowActive : DT.body)
                        .foregroundStyle(isRunning ? DT.text : DT.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    if !project.appBundleIDs.isEmpty {
                        AppIconRow(prefixes: project.appBundleIDs, installed: installed, size: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isRunning, sessionSeconds >= 1 {
                    Text(shortTime(sessionSeconds))
                        .font(DT.panelChip)
                        .foregroundStyle(DT.recording)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                }

                Text(hoursMinutes(todaySeconds))
                    .font(isRunning ? DT.panelTotalActive : DT.panelTotal)
                    .foregroundStyle(isRunning ? DT.text : DT.text2)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isRunning ? AnyShapeStyle(DT.recording.opacity(0.12)) :
                    hovering ? AnyShapeStyle(Color.white.opacity(0.04)) : AnyShapeStyle(.clear)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(PillView.spokenDuration(todaySeconds)) today"
                            + (isRunning ? ", running" : ""))
        .accessibilityHint("Switches the active project")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func hoursMinutes(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    private func shortTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
