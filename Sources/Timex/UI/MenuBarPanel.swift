import SwiftUI
import AppKit

/// The Klokki-inspired drop-down: hero header, project list, footer bar.
struct MenuBarPanel: View {
    @Bindable var model: AppModel
    /// With Reduce Transparency on, a material over the desktop is exactly
    /// what the user asked the system not to do — and it is the only reason
    /// this panel's contrast cannot be computed, since it depends on whatever
    /// wallpaper happens to be behind it.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isRecording: Bool { model.engine.state == .recording }
    private var accent: Color { DT.recording }

    var body: some View {
        VStack(spacing: 0) {
            hero
            projectList
            resumeBanner
            researchWindow
            receipt
            footer
        }
        .frame(width: 340)
        // Escape is handled by the controller with a key monitor, not here:
        // .onExitCommand depends on the SwiftUI responder chain reaching a
        // view hosted inside an NSPopover, which it does only sometimes — a
        // dismissal that works two runs in three is a keyboard trap.
        .accessibilityAddTraits(.isModal)
        .background(reduceTransparency ? AnyShapeStyle(DT.overlay) : AnyShapeStyle(.ultraThinMaterial))
        .background(reduceTransparency ? DT.overlay : DT.window.opacity(0.55))
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
        return "Today \(worked), \(project.name)\(client)"
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

    private func footBtn(_ label: String, help: String, action: @escaping () -> Void) -> some View {
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
