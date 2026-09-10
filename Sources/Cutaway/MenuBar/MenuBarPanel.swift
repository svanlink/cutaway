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
                       projectMismatch: Bool = false,
                       hasOtherProjects: Bool = false) -> [PanelBlock] {
        var b: [PanelBlock] = [.hero]
        // A failed save outranks everything: it is the one line that can
        // save the user money if they read it.
        if storeProblem { b.append(.storeProblem) }
        // "Nothing tracked yet" is a zero state a project can be IN, not
        // only one the app can be in — a project created a minute ago has no
        // time on it. Dropping the list there left the panel with no way to
        // switch back to the project that does have the day's work on it,
        // because the list shows the ones you are NOT tracking.
        if zeroState {
            return b + (hasOtherProjects ? [.zeroState, .projects] : [.zeroState]) + [.footer]
        }
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
                                 projectMismatch: model.projectMismatch,
                                 hasOtherProjects: model.projects.count > 1)
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
                // A 4 pt bar, not a 92 pt ring. The ring was a plain stroked
                // circle with no trim — it showed nothing, and a full ring
                // reads as a progress indicator sitting at 100%. It cost 92
                // points of a 300-point panel, which is why the project name
                // beside it truncated. State belongs in the colour, and the
                // colour is now a rule down the edge: accent while
                // recording, grey while paused.
                Rectangle()
                    .fill(isRecording ? accent : DT.ringPaused)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: DT.s1) {
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
                        .padding(.top, DT.s1)
                    Text(model.selectedProject?.name ?? "No project")
                        .font(DT.panelProject)
                        .foregroundStyle(DT.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, DT.rowInset)
                .padding(.vertical, DT.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(isRecording ? accent.opacity(0.12) : Color.white.opacity(0.04))
            }
            // 92 was the height of the ring that used to sit beside this.
            // With the ring gone the hero is four stacked lines in a box
            // sized for a circle, so the clock sat hard against the popover's
            // top edge. Let it size to its content with real margins.
            .fixedSize(horizontal: false, vertical: true)
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

    private var elapsedText: some View {
        let s = Int(model.todaySeconds)
        let main = String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
        let sec = String(format: ":%02d", s % 60)
        return HStack(alignment: .firstTextBaseline, spacing: DT.s1) {
            Text(main).font(DT.panelHero).foregroundStyle(DT.text)
            Text(sec).font(DT.panelHeroSeconds).foregroundStyle(DT.text2)
        }
        .monospacedDigit()
    }

    // MARK: - Project list

    private var projectList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // The OTHER projects. The one being tracked is the hero
                // directly above — showing it again as the first row repeated
                // its name and its time thirty points apart, which is most of
                // what made the panel feel stacked. A list under a "now"
                // readout is a list of what you could switch to.
                ForEach(model.projects.filter { $0.persistentModelID != model.selectedProjectID },
                        id: \.persistentModelID) { p in
                    PanelRow(
                        project: p,
                        todaySeconds: model.todaySecondsFor(p),
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
        // As tall as the rows need. A ScrollView claims every point it is
        // offered, so this used to reserve 176 for two projects.
        .frame(height: PanelLayout.listHeight(rowCount: max(model.projects.count - 1, 0)))
    }

    // MARK: - Research window

    /// The clock is held because Resolve is on something else. A stopped
    /// timer with no explanation is indistinguishable from a broken one.
    @ViewBuilder
    private var mismatchBanner: some View {
        if model.projectMismatch, let onScreen = model.resolveProject {
            HStack(spacing: DT.within) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(DT.glyph)
                VStack(alignment: .leading, spacing: DT.s1) {
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
            HStack(spacing: DT.within) {
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
                        .padding(.horizontal, DT.s3)
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
            HStack(spacing: DT.within) {
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
            HStack(spacing: DT.within) {
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
        // Two different facts, and the footer used only one of them.
        //
        // `manuallyPaused` says whether the owner pressed this button. It
        // does NOT say whether anything is being recorded — the engine is
        // also stopped when Resolve is not frontmost, when input has gone
        // idle, while a project is awaited, with no project at all, and
        // through sleep. In every one of those the footer drew a filled teal
        // "Pause", the app's primary control in its active styling, for a
        // clock that was already stopped, while the hero six points above
        // correctly showed nothing running. The pill agrees with the hero;
        // the footer was the one surface out of step.
        //
        // The ACTION is unchanged — this is the manual pause control, and
        // pausing ahead of time is a real thing to want. Only the claim is:
        // the filled accent now means "something is being recorded and this
        // stops it".
        return Button { model.engine.togglePause() } label: {
            HStack(spacing: DT.s1) {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(DT.buttonGlyph)
                Text(paused ? "Resume" : "Pause").font(DT.smallSemibold)
            }
            .foregroundStyle(isRecording ? DT.onSignal : DT.text)
            .padding(.horizontal, DT.s3)
            .frame(height: 26)
            .background(isRecording ? AnyShapeStyle(DT.signal) : AnyShapeStyle(Color.white.opacity(0.12)),
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
            footBtn("plus", help: "New Project") {
                model.showNewProjectSheet = true
                model.openMainWindow?()
            }
            Button { model.openMainWindow?() } label: {
                // A Label, not "Stats ↗". U+2197 is NORTH EAST ARROW, and
                // that is what VoiceOver said out loud.
                Label("Stats", systemImage: "arrow.up.forward.square")
                    .labelStyle(.titleAndIcon)
                    .font(DT.smallSemibold)
                    .foregroundStyle(DT.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Cutaway")
            footBtn("gearshape", help: "Settings") {
                // showSettingsWindow: was removed in macOS 14 — the old
                // silent-no-op bug. Settings is a real window we open.
                model.openSettingsWindow?()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, DT.s3)
        .background(Color.black.opacity(0.35))
    }

    /// An SF Symbol, not a typographic character.
    ///
    /// These were "＋" (U+FF0B FULLWIDTH PLUS SIGN) and "⚙" (U+2699 GEAR) —
    /// text pretending to be iconography, in a footer sitting under a toolbar
    /// that uses real symbols. Apple's guidance is SF Symbols for icons, and
    /// the practical difference is that a symbol aligns optically with text,
    /// takes a weight, and scales with the type; a character takes whatever
    /// the font happens to give it, which is why these two never quite
    /// matched each other or anything else.
    private func footBtn(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
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

/// One project you are NOT tracking, and could switch to.
///
/// The list filters the selected project out — the hero above is that
/// project — so this row's `isRunning` and `isSelected` were false by
/// construction, and every branch they guarded was unreachable: the running
/// ring, the live session chip, the active fonts, the recording background,
/// the ", running" suffix, the `.isSelected` trait. All deleted rather than
/// repaired; a row that cannot be the running one should not carry the code
/// for being it.
///
/// The visible cost of that dead code was a ▶ on every row. It is not a
/// button — nothing inside the row is; the row itself is one — and its
/// action switches the billing target without starting anything. With the
/// engine manually paused, or Resolve not frontmost, pressing it moved which
/// client was being billed and the clock stayed at zero. The accessible
/// label said "Switches the active project" all along, so a screen-reader
/// user was better informed than a sighted one. Now the glyph says what the
/// label says.
private struct PanelRow: View {
    let project: Project
    let todaySeconds: TimeInterval
    let installed: [InstalledApp]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DT.s3) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    Image(systemName: "arrow.left.arrow.right")
                        .font(DT.glyphTiny)
                        .foregroundStyle(DT.text3)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: DT.s1) {
                    Text(project.name)
                        .font(DT.body)
                        .foregroundStyle(DT.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    if !project.appBundleIDs.isEmpty {
                        AppIconRow(prefixes: project.appBundleIDs, installed: installed, size: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(hoursMinutes(todaySeconds))
                    .font(DT.panelTotal)
                    .foregroundStyle(DT.text2)
                    .monospacedDigit()
            }
            .padding(.horizontal, DT.rowInset)
            // A stated height, so the list's own height is arithmetic rather
            // than a guess. See PanelLayout.
            .frame(height: PanelLayout.rowHeight)
            .background(hovering ? AnyShapeStyle(Color.white.opacity(0.04)) : AnyShapeStyle(.clear))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Switch to this project")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(PillView.spokenDuration(todaySeconds)) today")
        .accessibilityHint("Switches the active project")
        .accessibilityAddTraits(.isButton)
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
