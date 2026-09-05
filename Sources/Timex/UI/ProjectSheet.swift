import SwiftUI

/// Create or edit a project — every billing field is editable after the
/// fact, because rates get negotiated and budgets get amended.
struct ProjectSheet: View {
    @Bindable var model: AppModel
    var editing: Project? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var client = ""
    @State private var mode: BillingMode = .hourly
    // Seeded from the shared defaults, not invented here — a project created
    // on this form and one auto-created from Resolve must agree.
    @State private var rate = AppModel.defaultHourlyRate
    @State private var budget: Double = 0
    @State private var currency: TimexCurrency = AppModel.defaultCurrency
    // Pre-ticked with the global list: the normal case needs zero clicks;
    // a narrow job (an InDesign-only template) is an untick.
    @State private var apps: Set<String> = Set(AppModel.globalWorkApps)

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Project name", text: $name, prompt: Text("e.g. Nyx Fashion Film"))
                    TextField("Client", text: $client, prompt: Text("optional"))
                }
                Section("Billing") {
                    Picker("Mode", selection: $mode) {
                        Text("Hourly").tag(BillingMode.hourly)
                        Text("Fixed budget").tag(BillingMode.budget)
                    }
                    .pickerStyle(.segmented)
                    TextField("Hourly rate", value: $rate, format: .number.precision(.fractionLength(2)))
                    if mode == .budget {
                        TextField("Budget", value: $budget, format: .number.precision(.fractionLength(0)))
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(TimexCurrency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if editing != nil {
                        Text("A new rate applies from now on. Work already recorded keeps the rate it was worked at.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    AppPickerView(selected: $apps)
                } header: {
                    Text("Apps")
                } footer: {
                    Text("Only these apps count toward this project.")
                }
            }
            .formStyle(.grouped)
            HStack {
                if isDuplicate {
                    Text("A project with this name already exists").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create Project" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isDuplicate || apps.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 600)
        .onAppear {
            guard let p = editing else { return }
            name = p.name
            client = p.client
            mode = p.mode
            rate = p.hourlyRate
            budget = p.budget
            currency = p.currency
            // A legacy project (empty list) shows the global list ticked; saving
            // it writes that list out explicitly — same behaviour, now visible.
            apps = p.appBundleIDs.isEmpty ? Set(AppModel.globalWorkApps) : Set(p.appBundleIDs)
        }
    }

    private var isDuplicate: Bool {
        let others = model.projects.filter { $0.persistentModelID != editing?.persistentModelID }
        return AppModel.isDuplicateName(name, existing: others.map(\.name))
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let c = client.trimmingCharacters(in: .whitespaces)
        let r = AppModel.clampedRate(rate)
        let b = max(0, budget)
        let a = Array(apps).sorted()
        if let p = editing {
            model.update(p, name: n, client: c, mode: mode, rate: r, budget: b, currency: currency, apps: a)
        } else {
            model.createProject(name: n, client: c, mode: mode, rate: r, budget: b,
                                currency: currency, apps: a, isManual: true)
        }
        dismiss()
    }
}
