import Foundation

/// The period an invoice covers. Presets rather than a date picker: the
/// question is always "bill last month", never "bill March 3rd to the 19th".
enum InvoicePeriod: String, CaseIterable, Sendable {
    case allTime = "All time"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case thisYear = "This year"

    /// Half-open [start, end) in day terms. nil = everything.
    func interval(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .allTime:
            return nil
        case .thisMonth:
            guard let start = calendar.dateInterval(of: .month, for: today)?.start,
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return (start, end)
        case .lastMonth:
            guard let thisStart = calendar.dateInterval(of: .month, for: today)?.start,
                  let start = calendar.date(byAdding: .month, value: -1, to: thisStart) else { return nil }
            return (start, thisStart)
        case .thisYear:
            guard let start = calendar.dateInterval(of: .year, for: today)?.start,
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
            return (start, end)
        }
    }

    /// Goes in the filename, so two invoices for one client stay apart.
    func fileLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let i = interval(now: now, calendar: calendar) else { return "all time" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone   // .calendar alone keeps the machine's zone
        f.dateFormat = self == .thisYear ? "yyyy" : "yyyy-MM"
        return f.string(from: i.start)
    }
}

/// Builds the 19-column CSV per spec. Pure string assembly — testable.
enum CSVExporter {

    static let header = [
        "date", "weekday", "project", "client", "billing_mode", "currency",
        "sessions_count", "first_start", "last_end", "active_hours", "adjusted_hours",
        "idle_excluded_hours", "hourly_rate", "earned", "budget_total",
        "budget_remaining", "budget_percent_used", "cumulative_hours",
        "cumulative_earned",
    ].joined(separator: ",")

    static func export(project name: String, client: String, mode: BillingMode,
                       currency: BillingCurrency, hourlyRate: Double, budget: Double,
                       days: [DayTotal], period: (start: Date, end: Date)? = nil,
                       calendar: Calendar = .current) -> String {
        // Filtering happens HERE, not at the call site: cumulative columns are
        // computed over whatever survives, so a caller that filtered wrongly
        // would produce a file that is wrong in a way that looks right.
        let inPeriod = period.map { p in
            days.filter { $0.day >= p.start && $0.day < p.end }
        } ?? days
        // chronological for cumulative columns
        let ordered = inPeriod.sorted { $0.day < $1.day }
        var lines = [header]
        var cumHours: Double = 0
        var cumEarned: Double = 0
        // POSIX locale pins Gregorian digits and English weekday names — a
        // client-facing CSV must not change shape with the Mac's locale
        // (e.g. Buddhist-era years, localized weekdays).
        let posix = Locale(identifier: "en_US_POSIX")
        let dateF = DateFormatter()
        dateF.locale = posix
        dateF.dateFormat = "yyyy-MM-dd"
        dateF.calendar = calendar
        dateF.timeZone = calendar.timeZone   // .calendar alone keeps the machine's zone
        let weekdayF = DateFormatter()
        weekdayF.locale = posix
        weekdayF.dateFormat = "EEE"
        weekdayF.calendar = calendar
        weekdayF.timeZone = calendar.timeZone   // .calendar alone keeps the machine's zone
        let timeF = DateFormatter()
        timeF.locale = posix
        timeF.dateFormat = "HH:mm"
        timeF.calendar = calendar
        timeF.timeZone = calendar.timeZone

        for d in ordered {
            // Round to the PRINTED precision before summing. Printing rounded
            // rows while totalling unrounded values is how an invoice ends up
            // one cent short of its own arithmetic — a small hole in a
            // document a client is paying against is a large credibility one.
            let hours = round2(d.activeSeconds / 3600)
            // The day carries what it earned, at the rates it was worked at.
            // Recomputing from the project's CURRENT rate is what used to
            // rewrite invoices that had already been sent.
            let earned = round2(d.earned)
            let rowRate = d.effectiveRate > 0 ? d.effectiveRate : hourlyRate
            cumHours += hours
            cumEarned += earned
            let wall = d.lastEnd.timeIntervalSince(d.firstStart)
            let idleExcluded = round2(max(wall - d.activeSeconds, 0) / 3600)
            let budgetRemaining = mode == .budget ? round2(budget - cumEarned) : 0
            let budgetPct = mode == .budget && budget > 0 ? cumEarned / budget * 100 : 0
            lines.append([
                dateF.string(from: d.day),
                weekdayF.string(from: d.day),
                csvEscape(name),
                csvEscape(client),
                mode.rawValue,
                currency.rawValue,
                String(d.sessionCount),
                timeF.string(from: d.firstStart),
                timeF.string(from: d.lastEnd),
                String(format: "%.2f", hours),
                String(format: "%.2f", round2(d.adjustedSeconds / 3600)),
                String(format: "%.2f", idleExcluded),
                String(format: "%.2f", rowRate),
                String(format: "%.2f", earned),
                mode == .budget ? String(format: "%.2f", budget) : "",
                mode == .budget ? String(format: "%.2f", budgetRemaining) : "",
                mode == .budget ? String(format: "%.1f", budgetPct) : "",
                String(format: "%.2f", cumHours),
                String(format: "%.2f", cumEarned),
            ].joined(separator: ","))
        }

        // summary block
        lines.append("")
        lines.append("summary")
        // The client must be able to see what span they are paying for
        // without inferring it from the rows.
        lines.append("period_start,\(ordered.first.map { dateF.string(from: $0.day) } ?? "")")
        lines.append("period_end,\(ordered.last.map { dateF.string(from: $0.day) } ?? "")")
        lines.append("total_days_worked,\(ordered.count)")
        lines.append("total_active_hours,\(String(format: "%.2f", cumHours))")
        lines.append("total_earned,\(String(format: "%.2f", cumEarned))")
        lines.append("billing_mode,\(mode.rawValue)")
        if mode == .budget {
            lines.append("budget,\(String(format: "%.2f", budget))")
            lines.append("budget_remaining,\(String(format: "%.2f", round2(budget - cumEarned)))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The precision every money and hours column prints at. Rounding once,
    /// here, is what keeps rows and totals in agreement.
    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func csvEscape(_ field: String) -> String {
        // Formula-injection guard: this file is meant to be opened by clients
        // in Excel/Numbers — a leading =,+,-,@ would execute as a formula.
        var f = field
        if let first = f.first, "=+-@".contains(first) {
            f = "'" + f
        }
        if f.contains(",") || f.contains("\"") || f.contains("\n") {
            return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return f
    }
}
