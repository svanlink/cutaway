import SwiftUI
import SwiftData

// MARK: - Mode tag (HOURLY / BUDGET)

struct ModeTag: View {
    let mode: BillingMode
    var prominent = false

    var body: some View {
        Text(mode == .hourly ? "HOURLY" : "BUDGET")
            .font(DT.tag)
            .foregroundStyle(prominent ? DT.signal : DT.text3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(prominent ? DT.signal.opacity(0.4) : DT.strokeSubtle, lineWidth: 1)
            )
    }
}

// MARK: - Switcher popover content (3 visible rows, scrolls, pinned footer)

struct SwitcherList: View {
    let projects: [Project]
    let currentID: PersistentIdentifier?
    let select: (Project) -> Void
    let newProject: () -> Void
    var onEdit: ((Project) -> Void)? = nil
    var onDelete: ((Project) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(projects, id: \.persistentModelID) { p in
                        SwitcherRow(project: p, isCurrent: p.persistentModelID == currentID) {
                            select(p)
                        }
                        .contextMenu {
                            if let onEdit {
                                Button("Edit…") { onEdit(p) }
                            }
                            if let onDelete {
                                Button("Delete…", role: .destructive) { onDelete(p) }
                            }
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
                    .fill(isCurrent ? DT.signal : DT.text3)
                    .frame(width: 7, height: 7)
                Text(project.name)
                    .font(DT.body)
                    .foregroundStyle(isCurrent ? DT.text : (hovering ? DT.text : DT.text2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                ModeTag(mode: project.mode)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isCurrent ? AnyShapeStyle(DT.signalSoft) :
                    hovering ? AnyShapeStyle(Color.white.opacity(0.06)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: DT.rSm)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
