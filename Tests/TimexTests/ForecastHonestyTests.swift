import XCTest
@testable import Cutaway

/// The demo build printed "≈ 10858.0 working days left at current pace" —
/// forty-three years, to one decimal place, from twenty-two seconds of
/// tracked work. The arithmetic was right and the sentence was a lie, and it
/// is the first thing a real user sees on day one of any budget project.
final class ForecastHonestyTests: XCTestCase {

    /// The exact case from the screenshot: a 4'500 budget, one day, 22s.
    func testTwentyTwoSecondsIsNotAPace() {
        let f = BillingEngine.forecast(remaining: 4499, avgDailySeconds: 22,
                                       hourlyRate: 85, daysWorked: 1)
        XCTAssertEqual(f, .paceUnknown)
        XCTAssertNil(BillingEngine.forecastLine(f),
                     "with nothing to say, the line must not appear at all")
    }

    func testOneDayIsASampleOfOne() {
        let f = BillingEngine.forecast(remaining: 4000, avgDailySeconds: 6 * 3600,
                                       hourlyRate: 85, daysWorked: 1)
        XCTAssertEqual(f, .paceUnknown, "a full day of work is still one data point")
    }

    func testTwoDaysIsEnoughToTrend() {
        let f = BillingEngine.forecast(remaining: 4000, avgDailySeconds: 6 * 3600,
                                       hourlyRate: 85, daysWorked: 2)
        guard case .days = f else { return XCTFail("expected a real forecast, got \(f)") }
    }

    func testABarelyThereDailyAverageIsNotAPace() {
        // Ten minutes a day across a fortnight: real days, unreal pace.
        let f = BillingEngine.forecast(remaining: 4000, avgDailySeconds: 10 * 60,
                                       hourlyRate: 85, daysWorked: 14)
        XCTAssertEqual(f, .paceUnknown, "below a quarter hour a day is noise amplified")
    }

    /// A slow but genuine pace: don't print a four-digit day count, say the
    /// thing a person would say.
    func testAVerySlowPaceIsReportedAsAHorizonNotANumber() {
        let f = BillingEngine.forecast(remaining: 100_000, avgDailySeconds: 30 * 60,
                                       hourlyRate: 85, daysWorked: 30)
        XCTAssertEqual(f, .beyondHorizon)
        XCTAssertEqual(BillingEngine.forecastLine(f), "More than a year left at current pace")
    }

    func testTheHorizonBoundaryIsAWorkingYear() {
        // Burn 1/day exactly: 250 days is inside, 251 is beyond.
        let rate = BillingEngine.earnings(activeSeconds: 3600, hourlyRate: 1)   // 1.0/day
        XCTAssertEqual(rate, 1, accuracy: 0.0001)
        guard case .days = BillingEngine.forecast(remaining: 250, avgDailySeconds: 3600,
                                                  hourlyRate: 1, daysWorked: 10)
        else { return XCTFail("250 days must still be a number") }
        XCTAssertEqual(BillingEngine.forecast(remaining: 251, avgDailySeconds: 3600,
                                              hourlyRate: 1, daysWorked: 10), .beyondHorizon)
    }

    /// Sub-day forecasts read absurdly as "≈ 0.4 working days".
    func testLessThanADayIsSaidInWords() {
        let f = BillingEngine.forecast(remaining: 100, avgDailySeconds: 6 * 3600,
                                       hourlyRate: 85, daysWorked: 5)
        XCTAssertEqual(BillingEngine.forecastLine(f),
                       "Less than a working day left at current pace")
    }

    func testARealForecastStillReadsNormally() {
        let f = BillingEngine.forecast(remaining: 990, avgDailySeconds: 4.6 * 3600,
                                       hourlyRate: 85, daysWorked: 6)
        XCTAssertEqual(BillingEngine.forecastLine(f),
                       "≈ 2.5 working days left at current pace")
    }

    func testNoForecastLineEverContainsAnAbsurdNumber() {
        // Sweep the space a real project can occupy; nothing may print a
        // day count in the thousands.
        for days in [1, 2, 5, 30, 200] {
            for avgMinutes in [1, 5, 16, 60, 240, 480] {
                for remaining in [10.0, 500.0, 4500.0, 50_000.0] {
                    let f = BillingEngine.forecast(remaining: remaining,
                                                   avgDailySeconds: Double(avgMinutes) * 60,
                                                   hourlyRate: 85, daysWorked: days)
                    if case .days(let d) = f {
                        XCTAssertLessThanOrEqual(d, BillingEngine.forecastHorizonDays,
                            "\(days)d × \(avgMinutes)min × \(remaining) printed \(d) days")
                    }
                }
            }
        }
    }
}
