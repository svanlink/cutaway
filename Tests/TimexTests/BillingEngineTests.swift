import XCTest
@testable import Cutaway

final class BillingEngineTests: XCTestCase {

    // MARK: - Hourly

    func testHourlyEarnings() {
        // 4.6h at 85/h = 391.00
        XCTAssertEqual(BillingEngine.earnings(activeSeconds: 4.6 * 3600, hourlyRate: 85), 391.00, accuracy: 0.001)
    }

    func testHourlyEarningsZeroSeconds() {
        XCTAssertEqual(BillingEngine.earnings(activeSeconds: 0, hourlyRate: 85), 0)
    }

    func testSpecFixture27_4HoursAt85() {
        // The design's Nyx fixture: 27.4h × 85 = 2329.00
        XCTAssertEqual(BillingEngine.earnings(activeSeconds: 27.4 * 3600, hourlyRate: 85), 2329.00, accuracy: 0.001)
    }

    // MARK: - Budget

    func testBudgetStatusHealthy() {
        let s = BillingEngine.budgetStatus(usedAmount: 578, budget: 2000)
        XCTAssertEqual(s.percentUsed, 28.9, accuracy: 0.01)
        XCTAssertEqual(s.remaining, 1422, accuracy: 0.001)
        XCTAssertEqual(s.warning, .none)
    }

    func testBudgetWarningAt75() {
        XCTAssertEqual(BillingEngine.budgetStatus(usedAmount: 1500, budget: 2000).warning, .warn75)
    }

    func testBudgetWarningAt90() {
        XCTAssertEqual(BillingEngine.budgetStatus(usedAmount: 1800, budget: 2000).warning, .warn90)
    }

    func testBudgetOverAt100() {
        let s = BillingEngine.budgetStatus(usedAmount: 2100, budget: 2000)
        XCTAssertEqual(s.warning, .over)
        XCTAssertEqual(s.remaining, -100, accuracy: 0.001)
    }

    func testAlpinaFixture() {
        // 41.3h × 85 = 3510.50 used of 4500 → 78% used, warn75
        let used = BillingEngine.earnings(activeSeconds: 41.3 * 3600, hourlyRate: 85)
        let s = BillingEngine.budgetStatus(usedAmount: used, budget: 4500)
        XCTAssertEqual(s.percentUsed, 78.0, accuracy: 0.1)
        XCTAssertEqual(s.warning, .warn75)
    }

    // MARK: - Pace forecast

    func testForecastWorkingDaysLeft() {
        // remaining 990, avg 4.6h/day at 85/h → 990 / 391 = 2.53 days
        let days = BillingEngine.forecastDaysLeft(remaining: 990, avgDailySeconds: 4.6 * 3600, hourlyRate: 85)
        XCTAssertNotNil(days)
        XCTAssertEqual(days!, 2.53, accuracy: 0.01)
    }

    func testForecastNilWhenNoPace() {
        XCTAssertNil(BillingEngine.forecastDaysLeft(remaining: 990, avgDailySeconds: 0, hourlyRate: 85))
    }

    func testForecastNilWhenOverBudget() {
        XCTAssertNil(BillingEngine.forecastDaysLeft(remaining: -10, avgDailySeconds: 3600, hourlyRate: 85))
    }

    // MARK: - Daily goal

    func testGoalProgressBelowGoal() {
        let g = BillingEngine.goalProgress(activeSeconds: 4.64 * 3600, goalSeconds: 8 * 3600)
        XCTAssertEqual(g.fraction, 0.58, accuracy: 0.001)
        XCTAssertEqual(g.overtimeSeconds, 0)
        XCTAssertFalse(g.reached)
    }

    func testGoalProgressOvertime() {
        let g = BillingEngine.goalProgress(activeSeconds: 8 * 3600 + 42 * 60, goalSeconds: 8 * 3600)
        XCTAssertEqual(g.fraction, 1.0)
        XCTAssertEqual(g.overtimeSeconds, 42 * 60)
        XCTAssertTrue(g.reached)
    }
}

final class CurrencyFormatterTests: XCTestCase {

    func testCHFSwissApostrophes() {
        XCTAssertEqual(TimexCurrency.chf.format(2329.25), "CHF 2'329.25")
        XCTAssertEqual(TimexCurrency.chf.format(393.75), "CHF 393.75")
    }

    func testCOPDotsNoDecimals() {
        XCTAssertEqual(TimexCurrency.cop.format(1_395_000), "COP 1.395.000")
        XCTAssertEqual(TimexCurrency.cop.format(180_000), "COP 180.000")
    }

    func testEUR() {
        XCTAssertEqual(TimexCurrency.eur.format(900), "€ 900.00")
        XCTAssertEqual(TimexCurrency.eur.format(2329.25), "€ 2'329.25")
    }

    func testUSD() {
        XCTAssertEqual(TimexCurrency.usd.format(393.75), "$ 393.75")
    }

    func testWholeNumberVariant() {
        // Stat rows show whole amounts without decimals
        XCTAssertEqual(TimexCurrency.chf.formatWhole(2329.25), "CHF 2'329")
    }
}

final class DaySplitterTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testSessionWithinOneDayNotSplit() {
        let rec = SessionRecord(start: date(2026, 7, 17, 10, 0), end: date(2026, 7, 17, 12, 0), activeSeconds: 7200)
        let parts = DaySplitter.split(rec, calendar: cal)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0].activeSeconds, 7200)
    }

    func testMidnightCrossingSplitsProportionally() {
        // 23:00 → 01:00, fully active (7200s): 3600 before midnight, 3600 after
        let rec = SessionRecord(start: date(2026, 7, 17, 23, 0), end: date(2026, 7, 18, 1, 0), activeSeconds: 7200)
        let parts = DaySplitter.split(rec, calendar: cal)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].activeSeconds, 3600, accuracy: 1)
        XCTAssertEqual(parts[1].activeSeconds, 3600, accuracy: 1)
        XCTAssertEqual(parts[0].end, date(2026, 7, 18, 0, 0))
        XCTAssertEqual(parts[1].start, date(2026, 7, 18, 0, 0))
    }

    func testActiveSecondsPreservedAcrossSplit() {
        // Partially active session across midnight keeps total active time
        let rec = SessionRecord(start: date(2026, 7, 17, 23, 30), end: date(2026, 7, 18, 0, 30), activeSeconds: 1800)
        let parts = DaySplitter.split(rec, calendar: cal)
        let total = parts.reduce(0) { $0 + $1.activeSeconds }
        XCTAssertEqual(total, 1800, accuracy: 1)
    }
}
