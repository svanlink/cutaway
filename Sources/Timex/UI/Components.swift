import SwiftUI
import SwiftData

// MARK: - Mode tag (HOURLY / BUDGET)

struct ModeTag: View {
    let mode: BillingMode
    var prominent = false

    var body: some View {
        Text(mode == .hourly ? "HOURLY" : "BUDGET")
            .font(DT.tag)
            .foregroundStyle(prominent ? DT.orange : DT.text3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(prominent ? DT.orange.opacity(0.4) : DT.strokeSubtle, lineWidth: 1)
            )
    }
}

// MARK: - Project pill (bottom of Timer view)

struct ProjectPill: View {
    let project: Project?
    let pointsUp: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(DT.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: DT.orange.opacity(0.8), radius: 4)
                Text(project?.name ?? "No project")
                    .font(DT.body)
                    .foregroundStyle(DT.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let p = project {
                    ModeTag(mode: p.mode, prominent: true)
                }
                Text(pointsUp ? "▲" : "▼")
                    .font(.system(size: 9))
                    .foregroundStyle(DT.text3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: 340)
            .background(hovering ? DT.orange.opacity(0.22) : DT.orangeSoft,
                        in: RoundedRectangle(cornerRadius: DT.rMd))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Current project: \(project?.name ?? "none"). Click to switch.")
    }
}

// MARK: - Switcher popover content (3 visible rows, scrolls, pinned footer)

struct SwitcherList: View {
    let projects: [Project]
    let currentID: PersistentIdentifier?
    let select: (Project) -> Void
    let newProject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(projects, id: \.persistentModelID) { p in
                        SwitcherRow(project: p, isCurrent: p.persistentModelID == currentID) {
                            select(p)
                        }
                    }
                }
            }
            .frame(maxHeight: 105)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 4)
            Button(action: newProject) {
                HStack(spacing: 10) {
                    Text("＋").font(DT.body)
                    Text("New Project…").font(DT.body)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DT.text3)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .padding(5)
        .frame(width: 250)
        .background(DT.popover)
    }
}

private struct SwitcherRow: View {
    let project: Project
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isCurrent ? DT.orange : DT.text3)
                    .frame(width: 7, height: 7)
                Text(project.name)
                    .font(DT.body)
                    .foregroundStyle(isCurrent ? DT.text : (hovering ? DT.text : DT.text2))
                    .lineLimit(1)
                Spacer(minLength: 8)
                ModeTag(mode: project.mode)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isCurrent ? AnyShapeStyle(DT.orangeSoft) :
                    hovering ? AnyShapeStyle(Color.white.opacity(0.06)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: DT.rSm)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Segmented Timer|Stats

struct SegmentedTabs: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 2) {
            seg("Timer", .timer)
            seg("Stats", .stats)
        }
        .padding(2)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DT.rMd))
    }

    @ViewBuilder
    private func seg(_ label: String, _ tab: MainTab) -> some View {
        let on = selection == tab
        Button { selection = tab } label: {
            Text(label)
                .font(DT.smallSemibold)
                .foregroundStyle(on ? DT.text : DT.text3)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(on ? AnyShapeStyle(DT.card2) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: DT.rSm))
                .shadow(color: on ? .black.opacity(0.4) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

enum MainTab { case timer, stats }
