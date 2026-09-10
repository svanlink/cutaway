import SwiftUI

/// First-run primer: what Cutaway asks for, why, and what it never does.
/// Shown once (PermissionsPrimerPolicy), reachable again from Settings.
struct PermissionsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent {
                        if model.detector.accessibilityGranted {
                            Text("Granted").foregroundStyle(.secondary)
                        } else {
                            Button("Enable…") { model.detector.requestAccessibility() }
                        }
                    } label: {
                        labelled("Accessibility",
                            "Reads Resolve's window title so the project switches when you do. Never controls your Mac.")
                    }
                    // No Automation row. This promised "Coming with Adobe
                    // project names: asks once per app, reads the document
                    // name only" — a feature cancelled on 2026-09-08 by the
                    // ruling that ONLY Resolve names projects. A welcome
                    // screen is the first thing a new owner reads, and this
                    // one was promising that the app would one day interrogate
                    // their Adobe applications. It will not.
                } header: {
                    Text("Permissions")
                } footer: {
                    Text(PermissionsPrimerPolicy.statement)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Continue") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle("What Cutaway needs, and why")
        // A grouped Form fills whatever it is given; this is a one-screen note.
        .frame(width: 480, height: 300)
        .onAppear { Prefs.set(true, forKey: "didShowPermissionsPrimer") }
    }
}
