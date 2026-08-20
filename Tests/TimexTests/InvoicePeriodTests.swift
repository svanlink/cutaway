import XCTest
@testable import Cutaway

/// Billing a month used to mean hand-editing the file in Excel — and the
/// cumulative columns were all-time, so the hand-edited file was wrong in a
/// way that looked right. A ranged export has to stand on its own.
final class InvoicePeriodTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: 9))!
    }

    private func day(_ y: Int, _ mo: Int, _ d: Int, hours: Double, rate: Double = 100) -> DayTotal {
        DayTotal(day: cal.startOfDay(for: date(y, mo, d)), activeSeconds: hours * 3600,
                 sessionCount: 1, firstStart: date(y, mo, d), lastEnd: date(y, mo, d),
                 earned: hours * rate)
    }

    /// June, July and August work — an invoice for July must contain July.
    private var threeMonths: [DayTotal] {
        [day(2026, 6, 29, hours: 2), day(2026, 7, 3, hours: 3),
         day(2026, 7, 28, hours: 1), day(2026, 8, 2, hours: 4)]
    }

    private func export(period: (start: Date, end: Date)?) -> String {
        CSVExporter.export(project: "Nyx", client: "", mode: .hourly, currency: .chf,
                           hourlyRate: 100, budget: 0, days: threeMonths,
                           period: period, calendar: cal)
    }

    func testRangedExportExcludesDaysOutsideIt() {
        let july = (start: cal.startOfDay(for: date(2026, 7, 1)),
                    end: cal.startOfDay(for: date(2026, 8, 1)))
        let csv = export(period: july)
        XCTAssertTrue(csv.contains("2026-07-03"))
        XCTAssertTrue(csv.contains("2026-07-28"))
        XCTAssertFalse(csv.contains("2026-06-29"), "June is a different invoice")
        XCTAssertFalse(csv.contains("2026-08-02"), "August has not been billed yet")
        XCTAssertTrue(csv.contains("total_days_worked,2"))
    }

    func testCumulativeColumnsRestartInsideThePeriod() {
        let july = (start: cal.startOfDay(for: date(2026, 7, 1)),
                    end: cal.startOfDay(for: date(2026, 8, 1)))
        let rows = export(period: july).split(separator: "\n").map(String.init)
        // First July row: 3h at 100 → cumulative must be its own figures, not
        // carrying June's 2h/200 in from a period the client is not paying for.
        XCTAssertTrue(rows[1].hasSuffix("3.00,300.00"), "got \(rows[1])")
        XCTAssertTrue(rows[2].hasSuffix("4.00,400.00"), "got \(rows[2])")
    }

    func testSummaryReconcilesWithItsOwnRows() {
        let july = (start: cal.startOfDay(for: date(2026, 7, 1)),
                    end: cal.startOfDay(for: date(2026, 8, 1)))
        let csv = export(period: july)
        XCTAssertTrue(csv.contains("total_active_hours,4.00"))
        XCTAssertTrue(csv.contains("total_earned,400.00"))
        XCTAssertTrue(csv.contains("period_start,2026-07-03"))
        XCTAssertTrue(csv.contains("period_end,2026-07-28"))
    }

    func testAllTimeIsUnfiltered() {
        let csv = export(period: nil)
        XCTAssertTrue(csv.contains("total_days_worked,4"))
        XCTAssertTrue(csv.contains("2026-06-29") && csv.contains("2026-08-02"))
    }

    func testEmptyPeriodProducesAnHonestlyEmptyFile() {
        let december = (start: cal.startOfDay(for: date(2026, 12, 1)),
                        end: cal.startOfDay(for: date(2026, 12, 31)))
        let csv = export(period: december)
        XCTAssertTrue(csv.contains("total_days_worked,0"), "no work is a real answer")
        XCTAssertTrue(csv.contains("total_earned,0.00"))
        XCTAssertTrue(csv.contains("period_start,"), "an empty period must not claim dates")
    }

    // MARK: - Presets

    func testLastMonthIsTheWholeOfLastMonth() {
        let now = date(2026, 8, 14)
        let i = try! XCTUnwrap(InvoicePeriod.lastMonth.interval(now: now, calendar: cal))
        XCTAssertEqual(i.start, cal.startOfDay(for: date(2026, 7, 1)))
        XCTAssertEqual(i.end, cal.startOfDay(for: date(2026, 8, 1)), "half-open: August is excluded")
    }

    func testThisMonthStartsAtTheFirst() {
        let i = try! XCTUnwrap(InvoicePeriod.thisMonth.interval(now: date(2026, 8, 14), calendar: cal))
        XCTAssertEqual(i.start, cal.startOfDay(for: date(2026, 8, 1)))
        XCTAssertEqual(i.end, cal.startOfDay(for: date(2026, 9, 1)))
    }

    func testLastMonthAcrossAYearBoundary() {
        let i = try! XCTUnwrap(InvoicePeriod.lastMonth.interval(now: date(2026, 1, 9), calendar: cal))
        XCTAssertEqual(i.start, cal.startOfDay(for: date(2025, 12, 1)))
        XCTAssertEqual(i.end, cal.startOfDay(for: date(2026, 1, 1)))
    }

    func testAllTimeHasNoInterval() {
        XCTAssertNil(InvoicePeriod.allTime.interval(now: date(2026, 8, 14), calendar: cal))
    }

    func testFileLabelsKeepTwoInvoicesApart() {
        XCTAssertEqual(InvoicePeriod.lastMonth.fileLabel(now: date(2026, 8, 14), calendar: cal), "2026-07")
        XCTAssertEqual(InvoicePeriod.thisMonth.fileLabel(now: date(2026, 8, 14), calendar: cal), "2026-08")
        XCTAssertEqual(InvoicePeriod.thisYear.fileLabel(now: date(2026, 8, 14), calendar: cal), "2026")
        XCTAssertEqual(InvoicePeriod.allTime.fileLabel(now: date(2026, 8, 14), calendar: cal), "all time")
    }
}
