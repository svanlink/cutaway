import SwiftUI
import SwiftData

/// Rename sheet — small, single field.
struct RenameProjectSheet: View {
    @Bindable var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s3) {
            Text("Rename Project").font(DT.title).foregroundStyle(DT.text)
            TextField("Project name", text: $name)
                .textFieldStyle(.plain)
                .font(DT.body)
                .foregroundStyle(DT.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DT.card2, in: RoundedRectangle(cornerRadius: DT.rMd))
                .overlay(RoundedRectangle(cornerRadius: DT.rMd).stroke(DT.strokeSubtle, lineWidth: 1))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename") {
                    model.rename(project, to: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(DT.orange)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DT.s4)
        .frame(width: 340)
        .background(DT.card)
        .onAppear { name = project.name }
    }
}

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
