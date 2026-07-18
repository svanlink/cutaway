import SwiftUI

struct NewProjectSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var client = ""
    @State private var mode: BillingMode = .hourly
    @State private var rate = "85.00"
    @State private var budget = ""
    @State private var currency: TimexCurrency = .chf

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s3) {
            Text("New Project").font(DT.title).foregroundStyle(DT.text)

            field("PROJECT NAME") {
                TextField("e.g. Nyx Fashion Film", text: $name).textFieldStyle(.plain)
            }
            field("CLIENT") {
                TextField("optional", text: $client).textFieldStyle(.plain)
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
                    TextField("85.00", text: $rate).textFieldStyle(.plain)
                }
                if mode == .budget {
                    field("BUDGET") {
                        TextField("4500", text: $budget).textFieldStyle(.plain)
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
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Project") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.orange)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Double(rate) == nil)
            }
            .padding(.top, DT.s1)
        }
        .padding(DT.s4)
        .frame(width: 400)
        .background(DT.card)
    }

    private func create() {
        model.createProject(
            name: name.trimmingCharacters(in: .whitespaces),
            client: client.trimmingCharacters(in: .whitespaces),
            mode: mode,
            rate: Double(rate) ?? 0,
            budget: Double(budget) ?? 0,
            currency: currency
        )
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
                .foregroundStyle(on ? DT.orange : DT.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(on ? AnyShapeStyle(DT.orangeSoft) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: DT.rSm))
        }
        .buttonStyle(.plain)
    }
}
