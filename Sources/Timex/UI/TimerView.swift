import SwiftUI

/// View 1 — the face. Ring, pause, detect line, project pill at the bottom.
struct TimerView: View {
    @Bindable var model: AppModel
    @State private var switcherOpen = false
    @State private var hoveringPause = false

    var body: some View {
        VStack(spacing: DT.s3) {
            // Equal spacers above and below center the cluster; the project
            // pill stays anchored at the bottom. No status pill here — the
            // ring's color/glow IS the state (one indicator per fact).
            Spacer(minLength: DT.s2)
            RingView(
                elapsed: model.todaySeconds,
                money: model.todayMoney,
                goal: model.goalProgress,
                goalHours: model.dailyGoalHours,
                isPaused: model.isPausedVisual
            )
            .padding(.top, DT.s1)

            // A zero state has nothing to pause. Swap the primary control for
            // the reason nothing is counting, and the way out of it.
            if let zero = model.zeroState {
                zeroStateCard(zero)
                    .padding(.top, DT.s3)
            } else {
                pauseButton
                    .padding(.top, DT.s3)
            }

            // Fixed extra below the cluster biases it slightly above center.
            Color.clear.frame(height: 28)
            Spacer(minLength: DT.s2)

            if model.shouldOfferAccessibility {
                accessibilityOffer
            }

            ProjectPill(project: model.selectedProject, pointsUp: true) {
                switcherOpen.toggle()
            }
            .popover(isPresented: $switcherOpen, arrowEdge: .top) {
                SwitcherList(
                    projects: model.projects,
                    currentID: model.selectedProjectID,
                    select: { model.selectManually($0); switcherOpen = false },
                    newProject: { switcherOpen = false; model.showNewProjectSheet = true },
                    onRename: { switcherOpen = false; model.editTarget = $0 },
                    onDelete: { switcherOpen = false; model.deleteTarget = $0 }
                )
            }
        }
        .padding(.horizontal, DT.s5)
        .padding(.bottom, DT.s4)
    }

    @ViewBuilder
    private func zeroStateCard(_ state: ZeroStatePolicy.ZeroState) -> some View {
        VStack(spacing: DT.s2) {
            Text(ZeroStatePolicy.zeroStateTitle(state))
                .font(DT.bodyBold)
                .foregroundStyle(DT.text)
            Text(ZeroStatePolicy.zeroStateHint(state))
                .font(DT.captionMedium)
                .foregroundStyle(DT.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state == .noProject {
                Button("Create your first project") { model.showNewProjectSheet = true }
                    .buttonStyle(.borderedProminent)
                    .tint(DT.signal)
                    .padding(.top, DT.s1)
            }
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, DT.s4)
        .padding(.vertical, DT.s3)
        .background(DT.card, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// Asked once, where the timer lives, with a real decline. Says what the
    /// user gets — not what the OS calls the permission.
    private var accessibilityOffer: some View {
        HStack(alignment: .top, spacing: DT.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follow project switches instantly")
                    .font(DT.smallSemibold)
                    .foregroundStyle(DT.text)
                Text("Cutaway can read Resolve's window title to switch projects the moment you do. It works without this — switching is just slower.")
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: DT.s1) {
                Button("Enable…") { model.detector.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .tint(DT.signal)
                Button("Not now") { model.accessibilityOfferDismissed = true }
                    .buttonStyle(.plain)
                    .font(DT.captionMedium)
                    .foregroundStyle(DT.text3)
            }
            .fixedSize()
        }
        .padding(.horizontal, DT.rowInset)
        .padding(.vertical, DT.s3)
        .background(DT.card, in: RoundedRectangle(cornerRadius: DT.rLg))
        .overlay(RoundedRectangle(cornerRadius: DT.rLg).stroke(DT.strokeSubtle, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var pauseButton: some View {
        let paused = model.engine.manuallyPaused
        return Button {
            model.engine.togglePause()
        } label: {
            HStack(spacing: DT.s2) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(DT.smallBold)
                Text(paused ? "Resume" : "Pause")
                    .font(DT.bodyBold)
            }
        }
        .buttonStyle(PauseButtonStyle(paused: paused, hovering: hoveringPause))
        .onHover { hoveringPause = $0 }
        .accessibilityLabel(paused ? "Resume timer" : "Pause timer")
    }
}

/// The app's primary control earns a real interaction design: a 44pt
/// target (Fitts), a lift-and-glow hover, and a compress on press —
/// not just a brightness tweak.
private struct PauseButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let paused: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(paused ? DT.textPrimary : DT.onSignal)
            .padding(.horizontal, 32)
            .frame(minHeight: 44)
            .background(
                paused ? AnyShapeStyle(DT.raised) : AnyShapeStyle(DT.signal),
                in: RoundedRectangle(cornerRadius: DT.rMd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.rMd)
                    .stroke(paused ? Color.white.opacity(hovering ? 0.24 : 0.14)
                                   : Color.white.opacity(hovering ? 0.25 : 0), lineWidth: 1)
            )

            .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.05 : 0))
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
