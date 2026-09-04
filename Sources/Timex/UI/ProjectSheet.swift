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
    @State private var rate = String(format: "%.2f", AppModel.defaultHourlyRate)
    @State private var budget = ""
    @State private var currency: TimexCurrency = AppModel.defaultCurrency

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s3) {
            Text(editing == nil ? "New Project" : "Edit Project").font(DT.title).foregroundStyle(DT.text)

            field("PROJECT NAME") {
                TextField("e.g. Nyx Fashion Film", text: $name).accessibilityLabel("Project name").textFieldStyle(.plain)
            }
            field("CLIENT") {
                TextField("optional", text: $client).accessibilityLabel("Client").textFieldStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("BILLING MODE")
                HStack(spacing: 2) {
                    modeSeg("Hourly", .hourly)
                    modeSeg("Fixed Budget", .budget)
                }
                .padding(2)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DT.rMd))
            }

            HStack(spacing: DT.s3) {
                field("HOURLY RATE") {
                    TextField(String(format: "%.2f", AppModel.defaultHourlyRate), text: $rate)
                        .accessibilityLabel("Hourly rate").textFieldStyle(.plain)
                }
                if mode == .budget {
                    field("BUDGET") {
                        TextField("4500", text: $budget).accessibilityLabel("Fixed budget").textFieldStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("CURRENCY")
                    Picker("", selection: $currency) {
                        ForEach(TimexCurrency.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }

            HStack {
                if isDuplicate {
                    Text("A project with this name already exists")
                        .font(DT.captionMedium)
                        .foregroundStyle(DT.amber)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create Project" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.signal)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || Double(rate) == nil || isDuplicate)
            }
            .padding(.top, DT.s1)
        }
        .padding(DT.s4)
        .frame(width: 400)
        .background(DT.card)
        .onAppear {
            guard let p = editing else { return }
            name = p.name
            client = p.client
            mode = p.mode
            rate = String(format: "%.2f", p.hourlyRate)
            budget = p.budget > 0 ? String(format: "%.0f", p.budget) : ""
            currency = p.currency
        }
    }

    private var isDuplicate: Bool {
        let others = model.projects.filter { $0.persistentModelID != editing?.persistentModelID }
        return AppModel.isDuplicateName(name, existing: others.map(\.name))
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let c = client.trimmingCharacters(in: .whitespaces)
        let r = AppModel.clampedRate(Double(rate) ?? 0)
        let b = max(0, Double(budget) ?? 0)
        if let p = editing {
            model.update(p, name: n, client: c, mode: mode, rate: r, budget: b, currency: currency)
        } else {
            model.createProject(name: n, client: c, mode: mode, rate: r, budget: b,
                                currency: currency, isManual: true)
        }
        dismiss()
    }

    private func label(_ t: String) -> some View {
        Text(t).font(DT.caption).kerning(0.55).foregroundStyle(DT.text3)
    }

    @ViewBuilder
    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            content()
                .font(DT.body)
                .foregroundStyle(DT.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DT.card2, in: RoundedRectangle(cornerRadius: DT.rMd))
                .overlay(RoundedRectangle(cornerRadius: DT.rMd).stroke(DT.strokeSubtle, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func modeSeg(_ title: String, _ m: BillingMode) -> some View {
        let on = mode == m
        Button { mode = m } label: {
            Text(title)
                .font(DT.smallSemibold)
                .foregroundStyle(on ? DT.signal : DT.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(on ? AnyShapeStyle(DT.signalSoft) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: DT.rSm))
        }
        .buttonStyle(.plain)
    }
}
