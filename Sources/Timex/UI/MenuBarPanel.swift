import SwiftUI
import AppKit

/// The Klokki-inspired drop-down: hero header, project list, footer bar.
struct MenuBarPanel: View {
    @Bindable var model: AppModel

    private var isRecording: Bool { model.engine.state == .recording }
    private var goalReached: Bool { model.goalProgress.reached }
    private var accent: Color { goalReached ? DT.green : DT.orange }

    var body: some View {
        VStack(spacing: 0) {
            hero
            projectList
            footer
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .background(DT.window.opacity(0.55))
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero

    /// The hero doubles as the way back into the app — click anywhere on
    /// it to open the main window on the Timer tab (stupid-proof reentry).
    private var hero: some View {
        Button {
            model.mainTab = .timer
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
                    Text(model.selectedProject?.client.isEmpty == false
                         ? model.selectedProject!.client.uppercased()
                         : "CUTAWAY")
                        .font(.system(size: 10.5, weight: .bold))
                        .kerning(0.84)
                        .foregroundStyle(isRecording ? accent : DT.text3)
                        .padding(.top, 3)
                    Text(model.selectedProject?.name ?? "No project")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DT.text)
                        .lineLimit(1)
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
        .accessibilityLabel("Open Cutaway")
        .help("Open Cutaway")
    }

    private var heroRing: some View {
        ZStack {
            Circle().stroke(DT.ringTrack, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(model.goalProgress.fraction, 0.01))
                .stroke(isRecording ? accent : DT.ringPaused,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: isRecording ? accent.opacity(0.6) : .clear, radius: 4)
        }
        .frame(width: 52, height: 52)
    }

    private var elapsedText: some View {
        let s = Int(model.todaySeconds)
        let main = String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
        let sec = String(format: ":%02d", s % 60)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(main).font(.system(size: 38, weight: .thin)).foregroundStyle(DT.text)
            Text(sec).font(.system(size: 20, weight: .light)).foregroundStyle(DT.text2)
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
                        sessionSeconds: model.engine.accumulator.activeSeconds
                    ) {
                        model.select(p)
                    }
                }
            }
        }
        .frame(maxHeight: 176)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            footBtn("＋", help: "New Project") {
                model.showNewProjectSheet = true
                model.openMainWindow?()
            }
            Button {
                model.mainTab = .stats
                model.openMainWindow?()
            } label: {
                Text("Stats ↗")
                    .font(.system(size: 12, weight: .semibold))
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

    private func footBtn(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isRunning ? AnyShapeStyle(DT.orange) : AnyShapeStyle(Color.white.opacity(0.08)))
                    if isRunning {
                        Circle()
                            .trim(from: 0, to: 0.75)
                            .stroke(DT.onOrange, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 11, height: 11)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(DT.text3)
                    }
                }
                .frame(width: 26, height: 26)

                Text(project.name)
                    .font(.system(size: 13, weight: isRunning ? .semibold : .medium))
                    .foregroundStyle(isRunning ? DT.text : DT.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isRunning, sessionSeconds >= 1 {
                    Text(shortTime(sessionSeconds))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(DT.orange)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                }

                Text(hoursMinutes(todaySeconds))
                    .font(.system(size: 12.5, weight: isRunning ? .bold : .semibold))
                    .foregroundStyle(isRunning ? DT.text : DT.text2)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isRunning ? AnyShapeStyle(DT.orangeSoft) :
                    hovering ? AnyShapeStyle(Color.white.opacity(0.04)) : AnyShapeStyle(.clear)
            )
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Switch to \(project.name)")
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
