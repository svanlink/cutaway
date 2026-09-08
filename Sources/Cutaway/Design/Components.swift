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

/// The small pencil/trash on a project row.
struct SwitcherIconButtonStyle: ButtonStyle {
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DT.glyph)
            .foregroundStyle(configuration.isPressed
                             ? (danger ? DT.red : DT.text)
                             : DT.text3)
            .frame(width: 24, height: 24)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06),
                        in: RoundedRectangle(cornerRadius: DT.rSm))
            .contentShape(RoundedRectangle(cornerRadius: DT.rSm))
    }
}

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
                        // Edit and delete were a context menu only, which is
                        // a secret: nothing on screen said a project could be
                        // changed or removed at all. The buttons are visible
                        // now, and the menu stays for the right-click habit.
                        HStack(spacing: 2) {
                            SwitcherRow(project: p, isCurrent: p.persistentModelID == currentID) {
                                select(p)
                            }
                            if let onEdit {
                                Button { onEdit(p) } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(SwitcherIconButtonStyle())
                                .help("Edit this project")
                                .accessibilityLabel("Edit \(p.name)")
                            }
                            if let onDelete {
                                Button { onDelete(p) } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(SwitcherIconButtonStyle(danger: true))
                                .help("Delete this project")
                                .accessibilityLabel("Delete \(p.name)")
                            }
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
        .frame(width: 300)
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
