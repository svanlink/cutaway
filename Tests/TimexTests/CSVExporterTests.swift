import XCTest
@testable import Cutaway

final class CSVExporterTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private var sampleDays: [DayTotal] {
        [
            DayTotal(day: cal.startOfDay(for: date(2026, 7, 16, 0)), activeSeconds: 6.9 * 3600,
                     sessionCount: 3, firstStart: date(2026, 7, 16, 9), lastEnd: date(2026, 7, 16, 17)),
            DayTotal(day: cal.startOfDay(for: date(2026, 7, 17, 0)), activeSeconds: 4.6 * 3600,
                     sessionCount: 2, firstStart: date(2026, 7, 17, 10), lastEnd: date(2026, 7, 17, 15, 30)),
        ]
    }

    func testHeaderMatchesSpecExactly() {
        XCTAssertEqual(CSVExporter.header,
            "date,weekday,project,client,billing_mode,currency,sessions_count,first_start,last_end,active_hours,idle_excluded_hours,hourly_rate,earned,budget_total,budget_remaining,budget_percent_used,cumulative_hours,cumulative_earned")
    }

    func testHourlyExportRows() {
        let csv = CSVExporter.export(project: "Nyx Fashion Film", client: "Nyx Studios",
                                     mode: .hourly, currency: .chf, hourlyRate: 85, budget: 0,
                                     days: sampleDays, calendar: cal)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], CSVExporter.header)
        // chronological: Jul 16 first
        XCTAssertTrue(lines[1].hasPrefix("2026-07-16,Thu,Nyx Fashion Film,Nyx Studios,hourly,CHF,3,09:00,17:00,6.90,"))
        XCTAssertTrue(lines[1].contains(",85.00,586.50,"))
        // cumulative on row 2: 11.5h, 977.50
        XCTAssertTrue(lines[2].hasSuffix("11.50,977.50"))
        // summary block
        XCTAssertTrue(csv.contains("total_days_worked,2"))
        XCTAssertTrue(csv.contains("total_active_hours,11.50"))
        XCTAssertTrue(csv.contains("total_earned,977.50"))
    }

    func testBudgetColumnsFilled() {
        let csv = CSVExporter.export(project: "Alpina", client: "", mode: .budget,
                                     currency: .chf, hourlyRate: 85, budget: 4500,
                                     days: sampleDays, calendar: cal)
        let lines = csv.split(separator: "\n").map(String.init)
        // row 1: budget 4500, remaining 4500-586.50=3913.50, pct 13.0
        XCTAssertTrue(lines[1].contains(",4500.00,3913.50,13.0,"))
        XCTAssertTrue(csv.contains("budget_remaining,3522.50"))
    }

    func testIdleExcludedHours() {
        let csv = CSVExporter.export(project: "P", client: "", mode: .hourly,
                                     currency: .chf, hourlyRate: 85, budget: 0,
                                     days: sampleDays, calendar: cal)
        // Jul 16: wall 8h, active 6.9h → idle excluded 1.10
        XCTAssertTrue(csv.contains(",6.90,1.10,"))
    }

    func testCommaInProjectNameIsEscaped() {
        let csv = CSVExporter.export(project: "Nyx, The Film", client: "", mode: .hourly,
                                     currency: .chf, hourlyRate: 85, budget: 0,
                                     days: sampleDays, calendar: cal)
        XCTAssertTrue(csv.contains("\"Nyx, The Film\""))
    }
}
