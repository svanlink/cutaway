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
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Delete “\(project.name)”?").font(.headline)
                    if sessionCount > 0 {
                        Text("It has \(sessionCount) recorded session\(sessionCount == 1 ? "" : "s").")
                        if !others.isEmpty {
                            Picker("Sessions", selection: $reassignID) {
                                Text("Delete the sessions too").tag(PersistentIdentifier?.none)
                                ForEach(others, id: \.persistentModelID) { p in
                                    Text("Move to \(p.name)").tag(Optional(p.persistentModelID))
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    let target = others.first { $0.persistentModelID == reassignID }
                    // Dismissing regardless meant a refused delete looked
                    // exactly like a successful one — the sheet closed, the
                    // project was still there, and the only word about it was
                    // a generic banner in another window. The store refuses
                    // whenever invoiced sessions would be destroyed, and that
                    // refusal names the invoice.
                    if model.delete(project, reassignTo: target) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400)
    }
}
