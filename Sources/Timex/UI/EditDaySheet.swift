import SwiftUI

/// Edit one day's total — as hours or as money, whichever the invoice needs.
/// The two fields are one value seen through the project's rate; only the
/// field NOT being typed in is rewritten, so typing is never fought.
struct EditDaySheet: View {
    @Bindable var model: AppModel
    let project: Project
    let target: DayEditTarget
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var hoursText = ""
    @State private var amountText = ""
    @FocusState private var focus: Field?

    private enum Field { case hours, amount }
    private var isAdding: Bool { target.day == nil }
    private var seconds: TimeInterval? { AppModel.seconds(fromHoursText: hoursText) }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s3) {
            Text(isAdding ? "Add Time" : "Edit \(dayLabel)").font(DT.title).foregroundStyle(DT.text)
            if isAdding {
                VStack(alignment: .leading, spacing: 6) {
                    label("DAY")
                    DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }
            HStack(alignment: .top, spacing: DT.s3) {
                field("TIME WORKED") {
                    TextField("h:mm", text: $hoursText).textFieldStyle(.plain).focused($focus, equals: .hours)
                }
                field("AMOUNT · \(project.currency.rawValue)") {
                    TextField("0.00", text: $amountText).textFieldStyle(.plain).focused($focus, equals: .amount)
                        .disabled(project.hourlyRate <= 0)
                }
            }
            Text(project.hourlyRate > 0
                 ? "@ \(String(format: "%.2f", project.hourlyRate)) \(project.currency.rawValue) / h — one value, two views"
                 : "Set an hourly rate on the project to edit by amount")
                .font(DT.captionMedium).foregroundStyle(DT.text3)
            HStack {
                if seconds == nil, !hoursText.isEmpty {
                    Text("Try 1:30, 1.5 or 90m").font(DT.captionMedium).foregroundStyle(DT.amber)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let s = seconds { model.setDaySeconds(s, on: day) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(DT.signal)
                .disabled(seconds == nil)
            }
        }
        .padding(DT.s4)
        .frame(width: 380)
        .background(DT.card)
        .onAppear {
            day = target.day ?? Date()
            var current: TimeInterval = 0
            if let d = target.day {
                current = model.dayTotalsIncludingLive(for: project)
                    .first { Calendar.current.isDate($0.day, inSameDayAs: d) }?.activeSeconds ?? 0
            }
            hoursText = AppModel.hoursText(current)
            amountText = money(current)
        }
        .onChange(of: hoursText) { _, new in
            guard focus == .hours, let s = AppModel.seconds(fromHoursText: new) else { return }
            amountText = money(s)
        }
        .onChange(of: amountText) { _, new in
            guard focus == .amount, project.hourlyRate > 0,
                  let a = Double(new.replacingOccurrences(of: ",", with: ".")), a >= 0 else { return }
            hoursText = AppModel.hoursText(a / project.hourlyRate * 3600)
        }
    }

    private var dayLabel: String {
        guard let d = target.day else { return "" }
        return Calendar.current.isDateInToday(d) ? "Today" : d.formatted(.dateTime.month(.abbreviated).day())
    }

    private func money(_ s: TimeInterval) -> String {
        String(format: "%.2f", BillingEngine.earnings(activeSeconds: s, hourlyRate: project.hourlyRate))
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
}
