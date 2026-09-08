import XCTest
@testable import Cutaway

/// The invoice's one promise to a client: the row adds up.
///
/// `InvoiceBuilder` bills to the minute and `InvoiceDocumentView` prints
/// h:mm, so a client with a calculator must be able to multiply what they
/// see and land on the amount beside it. Every test here checks a whole
/// range rather than an example, because the two defects these pin were
/// invisible at the values anyone would have picked by hand: 8:40 at
/// CHF 120 is exact, and so is every other round number.
final class InvoiceRowArithmeticTests: XCTestCase {

    /// A day of exactly `minutes` billable time at `rate`.
    private func day(minutes: Int, rate: Double) -> DayTotal {
        let seconds = TimeInterval(minutes * 60)
        return DayTotal(day: Date(timeIntervalSince1970: 1_800_000_000),
                        activeSeconds: seconds,
                        sessionCount: 1,
                        firstStart: Date(timeIntervalSince1970: 1_800_000_000),
                        lastEnd: Date(timeIntervalSince1970: 1_800_000_000 + seconds),
                        earned: rate * (seconds / 3600))
    }

    private func line(minutes: Int, rate: Double,
                      currency: BillingCurrency = .chf) -> InvoiceBuilder.Line {
        InvoiceBuilder.lines(for: [day(minutes: minutes, rate: rate)],
                             sessionUIDsByDay: [:],
                             currency: currency)[0]
    }

    /// The printed h:mm is the minute count that was billed — not one less.
    ///
    /// The quantity used to travel through a 6-decimal string, so 227 minutes
    /// became "3.783333", and 3.783333 × 60 floors to 226. A third of all
    /// minute counts printed a minute short, every one of them short, in the
    /// direction that makes an honest invoice look padded.
    func testThePrintedClockHoursAreTheMinutesThatWereBilled() {
        for minutes in 1...1440 {
            let expected = String(format: "%d:%02d", minutes / 60, minutes % 60)
            let printed = InvoiceDocumentView.clockHours(line(minutes: minutes, rate: 150).quantity)
            XCTAssertEqual(printed, expected, "\(minutes) minutes printed as \(printed)")
        }
    }

    /// A tie belongs to the client.
    ///
    /// `Money.round2` is half-down for exactly this reason, but the lossy
    /// hours term perturbed an exact half-rappen UPWARDS before the rounding
    /// ever saw it, so the tie went the wrong way. Only bites where rate/60
    /// carries three decimals ending in 5 — CHF 112.50 and 187.50 are both
    /// in this user's range.
    func testNoLineEverRoundsATieUp() {
        for rate in [50.0, 100.0, 112.50, 120.0, 150.0, 187.50] {
            for minutes in 1...1440 {
                let exact = Decimal(minutes) * Money.decimal(rate) / 60
                let expected = Money.rounded(exact, currency: .chf)
                let got = line(minutes: minutes, rate: rate).amount
                XCTAssertEqual(got, expected,
                               "\(minutes) min at \(rate): billed \(got), exact is \(exact)")
            }
        }
    }

    /// The document's stated contract, checked end to end: what is printed
    /// in the hours column, times what is printed in the rate column, is
    /// what is printed in the amount column.
    func testAClientCanMultiplyTheRowAndGetTheAmount() {
        for rate in [50.0, 112.50, 150.0, 187.50] {
            for minutes in stride(from: 1, through: 1440, by: 7) {
                let l = line(minutes: minutes, rate: rate)
                let printedHours = InvoiceDocumentView.clockHours(l.quantity)
                let parts = printedHours.split(separator: ":")
                let asMinutes = Int(parts[0])! * 60 + Int(parts[1])!
                let recomputed = Money.rounded(Decimal(asMinutes) * l.unitPrice / 60,
                                               currency: .chf)
                XCTAssertEqual(recomputed, l.amount,
                               "row reads \(printedHours) x \(l.unitPrice) but says \(l.amount)")
            }
        }
    }

    /// Zero-length days still behave: no crash, no negative, no NaN rate.
    func testADayWithLessThanAMinuteBillsNothing() {
        let l = line(minutes: 0, rate: 150)
        XCTAssertEqual(l.amount, 0)
        XCTAssertEqual(InvoiceDocumentView.clockHours(l.quantity), "0:00")
    }
}
