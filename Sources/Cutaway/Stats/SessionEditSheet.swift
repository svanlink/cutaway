import SwiftUI

/// One session, as a span: the day, the hour it started, the hour it ended.
///
/// The honest unit of a working day. Setting a day's TOTAL had to invent a
/// moment for the time to sit at, so a corrected day could say four hours
/// without being able to say when — and "when" is what a client asks about.
struct SessionEditSheet: View {
    @Bindable var model: AppModel
    let project: Project
    /// nil = adding a session that was never tracked.
    let editing: WorkSession?
    /// The day to start from when adding.
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var start = Date()
    @State private var end = Date()
    @State private var refusal: String?

    var body: some View {
        VStack(spacing: 0) {
            (editing == nil ? Text("Add a session") : Text("Edit this session"))
                .font(.headline)
                .padding(.top)
            Form {
                DatePicker("Day", selection: $date, displayedComponents: .date)
                    .disabled(editing != nil)
                DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $end, displayedComponents: .hourAndMinute)
                LabeledContent {
                    Text(billableText).monospacedDigit()
                } label: {
                    // Two branches, not a ternary inside `labelled`: the
                    // parameter is a LocalizedStringKey and each literal has
                    // to reach the catalog as its own key.
                    if editing == nil {
                        labelled("Billable", "The whole span")
                    } else {
                        labelled("Billable", "Scales with the span; excluded idle stays excluded")
                    }
                }
                if rate > 0 {
                    LabeledContent("Earns") {
                        Text(project.currency.format(BillingEngine.earnings(
                            activeSeconds: billableSeconds, hourlyRate: rate)))
                            .monospacedDigit()
                    }
                }
                if let refusal {
                    Text(refusal).font(.caption).foregroundStyle(.orange)
                }
                Text("Entered by hand, and marked as such on the day, in the CSV and on the invoice.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)
            HStack {
                if let editing {
                    Button("Delete", role: .destructive) { delete(editing) }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(seconds <= 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, DT.s4)
            .background(.regularMaterial)
        }
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private var seconds: TimeInterval { combined(end).timeIntervalSince(combined(start)) }

    /// What pressing Save will actually store — not the span.
    ///
    /// `updateSession` scales a session's active seconds by how much the span
    /// changed, deliberately: a 13:00–17:00 session holding 2:30 of work must
    /// not become four billable hours because it was nudged sideways. The
    /// sheet printed the SPAN under "Length" and priced the span under
    /// "Earns", so opening an idle-trimmed session showed 4:00 and CHF 340
    /// before anything had been touched, and Save stored 2:30. Every number
    /// on the correction surface was wrong, in the over-billing direction.
    private var billableSeconds: TimeInterval {
        let span = max(seconds, 0)
        guard let editing else { return span }        // a typed span bills all of itself
        let oldSpan = editing.end.timeIntervalSince(editing.start)
        let ratio = oldSpan > 0 ? span / oldSpan : 1
        return min(editing.activeSeconds * ratio, span)
    }

    /// The rate this work was WORKED at, like every other billing surface.
    /// The project's current rate reprices history that a raise is promised
    /// not to touch.
    private var rate: Double {
        if let editing, editing.hourlyRate > 0 { return editing.hourlyRate }
        return project.hourlyRate
    }

    private var billableText: String {
        guard billableSeconds > 0 else { return String(localized: "—") }
        return AppModel.hoursText(billableSeconds)
    }

    /// The pickers edit a time; the day comes from the date field.
    private func combined(_ time: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: date) ?? date
    }

    private func load() {
        if let editing {
            date = editing.start
            start = editing.start
            end = editing.end
        } else {
            date = day
            let cal = Calendar.current
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }
    }

    private func save() {
        refusal = nil
        do {
            if let editing {
                try model.editSession(editing, from: combined(start), to: combined(end), in: project)
            } else {
                try model.addSession(from: combined(start), to: combined(end), to: project)
            }
            dismiss()
        } catch {
            refusal = error.localizedDescription
        }
    }

    private func delete(_ session: WorkSession) {
        refusal = nil
        do {
            try model.deleteSession(session, in: project)
            dismiss()
        } catch {
            refusal = error.localizedDescription
        }
    }
}
