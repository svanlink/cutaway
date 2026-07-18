import Foundation

/// Builds the 18-column CSV per spec. Pure string assembly — testable.
enum CSVExporter {

    static let header = [
        "date", "weekday", "project", "client", "billing_mode", "currency",
        "sessions_count", "first_start", "last_end", "active_hours",
        "idle_excluded_hours", "hourly_rate", "earned", "budget_total",
        "budget_remaining", "budget_percent_used", "cumulative_hours",
        "cumulative_earned",
    ].joined(separator: ",")

    static func export(project name: String, client: String, mode: BillingMode,
                       currency: TimexCurrency, hourlyRate: Double, budget: Double,
                       days: [DayTotal], calendar: Calendar = .current) -> String {
        // chronological for cumulative columns
        let ordered = days.sorted { $0.day < $1.day }
        var lines = [header]
        var cumSeconds: TimeInterval = 0
        var cumEarned: Double = 0
        let dateF = DateFormatter()
        dateF.dateFormat = "yyyy-MM-dd"
        dateF.calendar = calendar
        let weekdayF = DateFormatter()
        weekdayF.dateFormat = "EEE"
        weekdayF.calendar = calendar
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"
        timeF.calendar = calendar

        for d in ordered {
            let earned = BillingEngine.earnings(activeSeconds: d.activeSeconds, hourlyRate: hourlyRate)
            cumSeconds += d.activeSeconds
            cumEarned += earned
            let wall = d.lastEnd.timeIntervalSince(d.firstStart)
            let idleExcluded = max(wall - d.activeSeconds, 0)
            let budgetRemaining = mode == .budget ? budget - cumEarned : 0
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
                String(format: "%.2f", d.activeSeconds / 3600),
                String(format: "%.2f", idleExcluded / 3600),
                String(format: "%.2f", hourlyRate),
                String(format: "%.2f", earned),
                mode == .budget ? String(format: "%.2f", budget) : "",
                mode == .budget ? String(format: "%.2f", budgetRemaining) : "",
                mode == .budget ? String(format: "%.1f", budgetPct) : "",
                String(format: "%.2f", cumSeconds / 3600),
                String(format: "%.2f", cumEarned),
            ].joined(separator: ","))
        }

        // summary block
        lines.append("")
        lines.append("summary")
        lines.append("total_days_worked,\(ordered.count)")
        lines.append("total_active_hours,\(String(format: "%.2f", cumSeconds / 3600))")
        lines.append("total_earned,\(String(format: "%.2f", cumEarned))")
        lines.append("billing_mode,\(mode.rawValue)")
        if mode == .budget {
            lines.append("budget,\(String(format: "%.2f", budget))")
            lines.append("budget_remaining,\(String(format: "%.2f", budget - cumEarned))")
        }
        return lines.joined(separator: "\n") + "\n"
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
