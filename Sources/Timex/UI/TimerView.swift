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
                    newProject: { switcherOpen = false; model.showNewProjectSheet = true }
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
                    .font(.system(size: 11, weight: .bold))
                Text(paused ? "Resume" : "Pause")
                    .font(DT.bodyBold)
            }
            .foregroundStyle(paused ? DT.text : DT.onOrange)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(
                paused ? AnyShapeStyle(DT.card2) : AnyShapeStyle(DT.orange),
                in: RoundedRectangle(cornerRadius: DT.rMd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.rMd)
                    .stroke(paused ? Color.white.opacity(0.14) : .clear, lineWidth: 1)
            )
            .brightness(hoveringPause && !paused ? 0.06 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hoveringPause = $0 }
        .accessibilityLabel(paused ? "Resume timer" : "Pause timer")
    }
}
