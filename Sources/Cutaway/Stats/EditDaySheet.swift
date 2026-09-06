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
        VStack(spacing: 0) {
            Text(isAdding ? "Add Time" : "Edit \(dayLabel)")
                .font(.headline)
                .padding(.top)
            Form {
                if isAdding {
                    DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                }
                TextField("Time worked", text: $hoursText, prompt: Text("h:mm"))
                    .focused($focus, equals: .hours)
                TextField("Amount · \(project.currency.rawValue)", text: $amountText, prompt: Text("0.00"))
                    .focused($focus, equals: .amount)
                    .disabled(project.hourlyRate <= 0)
                Text(project.hourlyRate > 0
                     ? "@ \(String(format: "%.2f", project.hourlyRate)) \(project.currency.rawValue) / h — one value, two views"
                     : "Set an hourly rate on the project to edit by amount")
                    .font(.caption).foregroundStyle(.secondary)
                if seconds == nil, !hoursText.isEmpty {
                    Text("Try 1:30, 1.5 or 90m").font(.caption).foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let s = seconds { model.setDaySeconds(s, on: day) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(seconds == nil)
            }
            .padding()
        }
        .frame(width: 420)
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
        return Calendar.current.isDateInToday(d) ? String(localized: "Today") : d.formatted(.dateTime.month(.abbreviated).day())
    }

    private func money(_ s: TimeInterval) -> String {
        String(format: "%.2f", BillingEngine.earnings(activeSeconds: s, hourlyRate: project.hourlyRate))
    }
}
