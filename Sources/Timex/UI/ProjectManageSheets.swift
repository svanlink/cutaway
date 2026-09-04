import SwiftUI
import SwiftData

/// Delete sheet — the sessions decision is explicit, never implicit.
struct DeleteProjectSheet: View {
    @Bindable var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var reassignID: PersistentIdentifier?

    private var others: [Project] {
        model.projects.filter { $0.persistentModelID != project.persistentModelID }
    }
    private var sessionCount: Int { project.sessions.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s3) {
            Text("Delete “\(project.name)”?").font(DT.title).foregroundStyle(DT.text)
            if sessionCount > 0 {
                Text("It has \(sessionCount) recorded session\(sessionCount == 1 ? "" : "s").")
                    .font(DT.body).foregroundStyle(DT.text2)
                if !others.isEmpty {
                    Picker("Sessions", selection: $reassignID) {
                        Text("Delete the sessions too").tag(PersistentIdentifier?.none)
                        ForEach(others, id: \.persistentModelID) { p in
                            Text("Move to \(p.name)").tag(Optional(p.persistentModelID))
                        }
                    }
                    .labelsHidden()
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    let target = others.first { $0.persistentModelID == reassignID }
                    model.delete(project, reassignTo: target)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.red)
            }
        }
        .padding(DT.s4)
        .frame(width: 360)
        .background(DT.card)
    }
}
