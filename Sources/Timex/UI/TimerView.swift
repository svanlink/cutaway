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

            pauseButton
                .padding(.top, DT.s3)

            // Fixed extra below the cluster biases it slightly above center.
            Color.clear.frame(height: 28)
            Spacer(minLength: DT.s2)

            ProjectPill(project: model.selectedProject, pointsUp: true) {
                switcherOpen.toggle()
            }
            .popover(isPresented: $switcherOpen, arrowEdge: .top) {
                SwitcherList(
                    projects: model.projects,
                    currentID: model.selectedProjectID,
                    select: { model.select($0); switcherOpen = false },
                    newProject: { switcherOpen = false; model.showNewProjectSheet = true },
                    onRename: { switcherOpen = false; model.renameTarget = $0 },
                    onDelete: { switcherOpen = false; model.deleteTarget = $0 }
                )
            }
        }
        .padding(.horizontal, DT.s5)
        .padding(.bottom, DT.s4)
    }

    private var pauseButton: some View {
        let paused = model.engine.manuallyPaused
        return Button {
            model.engine.togglePause()
        } label: {
            HStack(spacing: DT.s2) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .bold))
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
    let paused: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(paused ? DT.text : DT.onOrange)
            .padding(.horizontal, 32)
            .frame(minHeight: 44)
            .background(
                paused ? AnyShapeStyle(DT.card2) : AnyShapeStyle(DT.orange),
                in: RoundedRectangle(cornerRadius: DT.rMd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.rMd)
                    .stroke(paused ? Color.white.opacity(hovering ? 0.24 : 0.14)
                                   : Color.white.opacity(hovering ? 0.25 : 0), lineWidth: 1)
            )
            .shadow(color: paused ? .clear : DT.orange.opacity(hovering ? 0.45 : 0.22),
                    radius: hovering ? 14 : 8, y: 3)
            .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.05 : 0))
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
