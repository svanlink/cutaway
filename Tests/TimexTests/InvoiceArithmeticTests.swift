import XCTest
@testable import Cutaway

/// A client who adds up the rows must get the total. Rows used to print
/// rounded to cents while the total printed the rounded sum of UNROUNDED
/// values, so the two could disagree — a one-cent hole in a document
/// somebody is paying against.
final class InvoiceArithmeticTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func days(_ seconds: [TimeInterval], rate: Double) -> [DayTotal] {
        seconds.enumerated().map { i, s in
            let d = cal.date(from: DateComponents(year: 2026, month: 3, day: i + 1, hour: 9))!
            return DayTotal(day: cal.startOfDay(for: d), activeSeconds: s, sessionCount: 1,
                            firstStart: d, lastEnd: d.addingTimeInterval(s),
                            earned: s / 3600 * rate)
        }
    }

    private func export(_ ds: [DayTotal], mode: BillingMode = .hourly,
                        budget: Double = 0, rate: Double = 85) -> String {
        CSVExporter.export(project: "P", client: "", mode: mode, currency: .chf,
                           hourlyRate: rate, budget: budget, days: ds, calendar: cal)
    }

    /// Day rows only — `split` drops the blank line before the summary, so a
    /// naive `prefix(while:)` walks straight into "total_days_worked,12".
    private func column(_ csv: String, _ index: Int) -> [Double] {
        let lines: [String] = csv.split(separator: "\n").map(String.init)
        var values: [Double] = []
        for line in lines.dropFirst() {
            let fields: [String] = line.components(separatedBy: ",")
            guard fields.count == 18, let v = Double(fields[index]) else { continue }
            values.append(v)
        }
        return values
    }

    private func summary(_ csv: String, _ key: String) -> String? {
        let lines: [String] = csv.split(separator: "\n").map(String.init)
        let prefix: String = key + ","
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    /// A month that genuinely does not add up under THIS app's arithmetic:
    /// 22 days at 157/h where totalling the unrounded day values lands on
    /// 15651.24 while the printed rows sum to 15651.25.
    ///
    /// The 12-day fixture named in the audit turned out to drift only under
    /// Python's half-to-even rounding, not Swift's half-away-from-zero — the
    /// defect class was real, that particular example was not. Re-found under
    /// the app's own semantics rather than kept because it read well.
    func testAMonthThatDidNotAddUp() {
        let secs: [TimeInterval] = [3344, 26562, 30287, 10921, 1583, 35227, 4739, 4502,
                                    2936, 13065, 16455, 2571, 31004, 21983, 29470, 13400,
                                    34621, 15912, 19877, 33353, 901, 6169]
        let csv = export(days(secs, rate: 157), rate: 157)

        let earnedSum: Double = column(csv, 12).reduce(0, +)
        XCTAssertEqual(summary(csv, "total_earned"), String(format: "%.2f", earnedSum),
                       "the total must be what the rows add up to")

        // The drift is real and gone: totalling UNROUNDED values — what the
        // exporter used to do — lands a cent away from the printed rows.
        let unrounded: Double = secs.reduce(0) { $0 + $1 / 3600 * 157 }
        XCTAssertNotEqual(String(format: "%.2f", unrounded),
                          String(format: "%.2f", earnedSum),
                          "this fixture exists because the two disagree")
    }

    /// The same defect in the hours column, which an invoice reader checks
    /// just as readily: 107.03 printed vs 107.02 summed unrounded.
    func testAMonthWhoseHoursDidNotAddUp() {
        let secs: [TimeInterval] = [17340, 24096, 35336, 2500, 31115, 16921, 3998, 10879,
                                    8019, 24965, 31340, 16759, 25553, 7282, 16940, 1459,
                                    14803, 27348, 18916, 12532, 26122, 11059]
        let csv = export(days(secs, rate: 85))

        let hoursSum: Double = column(csv, 9).reduce(0, +)
        XCTAssertEqual(summary(csv, "total_active_hours"), String(format: "%.2f", hoursSum))

        let unrounded: Double = secs.reduce(0) { $0 + $1 / 3600 }
        XCTAssertNotEqual(String(format: "%.2f", unrounded),
                          String(format: "%.2f", hoursSum),
                          "this fixture exists because the two disagree")
    }

    /// The invariant, not just the one case: across many shapes of month, the
    /// printed rows always sum to the printed total.
    func testRowsAlwaysSumToTheTotal() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let n = Int.random(in: 1...28, using: &generator)
            let secs = (0..<n).map { _ in TimeInterval(Int.random(in: 600...36000, using: &generator)) }
            let rate = Double(Int.random(in: 40...250, using: &generator))
            let csv = export(days(secs, rate: rate))

            let earnedSum = column(csv, 12).reduce(0, +)
            let hoursSum = column(csv, 9).reduce(0, +)
            XCTAssertEqual(summary(csv, "total_earned"), String(format: "%.2f", earnedSum),
                           "\(n) days at \(rate)/h: rows and total disagree")
            XCTAssertEqual(summary(csv, "total_active_hours"), String(format: "%.2f", hoursSum),
                           "\(n) days at \(rate)/h: hours rows and total disagree")
        }
    }

    /// The last cumulative row IS the total — they are the same number
    /// reached two ways, and a client will check exactly that.
    func testFinalCumulativeRowEqualsTheSummaryTotal() {
        let secs: [TimeInterval] = [17597, 15957, 13166, 31419, 31818, 26626]
        let csv = export(days(secs, rate: 85))
        let lastCumulative = column(csv, 17).last
        XCTAssertEqual(summary(csv, "total_earned"), String(format: "%.2f", lastCumulative ?? -1))
    }

    /// Asserted as an internal invariant rather than against a literal: a
    /// hardcoded expectation computed elsewhere just imports that tool's
    /// rounding mode into this one's test.
    func testBudgetRemainingAgreesWithTheEarnedTotal() {
        let secs: [TimeInterval] = [17597, 15957, 13166, 31419, 31818, 26626,
                                    10470, 15799, 10536, 34887, 26154, 1592]
        let csv = export(days(secs, rate: 85), mode: .budget, budget: 9000)
        let earnedText: String = summary(csv, "total_earned") ?? ""
        let earned: Double = Double(earnedText) ?? -1
        let expected: String = String(format: "%.2f", 9000 - earned)
        XCTAssertEqual(summary(csv, "budget_remaining"), expected,
                       "what is left must be the budget minus what the invoice says was earned")
    }
}
