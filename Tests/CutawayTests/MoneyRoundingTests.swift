import XCTest
@testable import Cutaway

/// One rounding rule, or the CSV a client receives disagrees with the window
/// the owner quoted from. Found 2026-09-07: the exporter rounded half away
/// from zero, the formatter half to even.
final class MoneyRoundingTests: XCTestCase {

    /// The case that exposed it: CHF 45/h over 3'610 s is exactly 45.125.
    func testTheExporterAndTheFormatterAgreeOnAnExactHalfRappen() {
        let earned = BillingEngine.earnings(activeSeconds: 3_610, hourlyRate: 45)
        XCTAssertEqual(earned, 45.125, accuracy: 1e-9, "the tie that used to split the two surfaces")
        XCTAssertEqual(CSVExporter.round2(earned), 45.12, accuracy: 1e-9)
        XCTAssertEqual(BillingCurrency.chf.format(earned), "CHF 45.12")
    }

    /// Ties resolve DOWN, like every other ambiguity in the app.
    ///
    /// "Tie" means a tie in the number the machine actually holds. Dyadic
    /// values (eighths, sixteenths) are stored exactly and really do land on
    /// the half-rappen; a literal like 2.345 does NOT — the nearest double is
    /// slightly ABOVE it, so rounding up is the correct nearest answer and
    /// the last two assertions pin that rather than pretend otherwise.
    func testTiesGoToTheClient() {
        XCTAssertEqual(Money.round2(45.125), 45.12, accuracy: 1e-9)   // 1/8
        XCTAssertEqual(Money.round2(2.375), 2.37, accuracy: 1e-9)     // 3/8
        XCTAssertEqual(Money.round2(0.125), 0.12, accuracy: 1e-9)
        // Not ties — ordinary rounding to the nearest rappen.
        XCTAssertEqual(Money.round2(2.3451), 2.35, accuracy: 1e-9)
        XCTAssertEqual(Money.round2(2.344), 2.34, accuracy: 1e-9)
        XCTAssertEqual(Money.round2(2.345), 2.35, accuracy: 1e-9)
    }

    /// A budget overrun must never be made to look smaller than it is.
    func testAnOverrunIsNeverFlattered() {
        XCTAssertEqual(Money.round2(-45.125), -45.13, accuracy: 1e-9)
    }

    /// Round each day, then sum — never sum raw and round the total.
    func testTheTotalIsTheSumOfThePrintedDays() {
        let days = [3_610.0, 3_610.0, 3_610.0].map {
            CSVExporter.round2(BillingEngine.earnings(activeSeconds: $0, hourlyRate: 45))
        }
        XCTAssertEqual(days.reduce(0, +), 135.36, accuracy: 1e-9)
        XCTAssertEqual(BillingCurrency.chf.format(days.reduce(0, +)), "CHF 135.36")
    }
}

/// Decimal is what a frozen invoice line is made of. It has to agree with the
/// Double path to the rappen, or the PDF and the Stats window disagree again —
/// the bug this whole rule exists to close.
final class DecimalMoneyTests: XCTestCase {

    func testDecimalAndDoubleAgreeOnTheTieThatStartedThis() {
        let seconds: TimeInterval = 3_610
        let rate = 45.0
        let exact = Money.amount(activeSeconds: seconds, hourlyRate: rate)
        XCTAssertEqual(exact, Decimal(string: "45.125"))
        XCTAssertEqual(Money.rounded(exact, currency: .chf), Decimal(string: "45.12"))
        XCTAssertEqual(NSDecimalNumber(decimal: Money.rounded(exact, currency: .chf)).doubleValue,
                       CSVExporter.round2(BillingEngine.earnings(activeSeconds: seconds, hourlyRate: rate)),
                       accuracy: 1e-9)
    }

    /// The reason Decimal is here at all.
    func testADecimalRateIsNotAnApproximation() {
        XCTAssertEqual(Money.decimal(45.55), Decimal(string: "45.550000"))
        let ten = Money.amount(activeSeconds: 36_000, hourlyRate: 45.55)
        XCTAssertEqual(Money.rounded(ten, currency: .chf), Decimal(string: "455.50"))
    }

    func testMinorUnitsFollowTheCurrency() {
        XCTAssertEqual(Money.minorUnits(.chf), 2)
        XCTAssertEqual(Money.minorUnits(.eur), 2)
        XCTAssertEqual(Money.minorUnits(.usd), 2)
        XCTAssertEqual(Money.minorUnits(.cop), 0, "no centavos on a Colombian invoice")
        // Nearest, not truncation — 1'234.56 really is nearer to 1'235.
        XCTAssertEqual(Money.rounded(Decimal(string: "1234.56")!, currency: .cop), Decimal(1235))
        XCTAssertEqual(Money.rounded(Decimal(string: "1234.44")!, currency: .cop), Decimal(1234))
        XCTAssertEqual(Money.rounded(Decimal(string: "1234.50")!, currency: .cop), Decimal(1234),
                       "a tie goes down here too")
    }

    func testAnOverrunIsNeverFlattered() {
        XCTAssertEqual(Money.rounded(Decimal(string: "-45.125")!, currency: .chf), Decimal(string: "-45.13"))
    }

    func testTotalIsTheSumOfRoundedParts() {
        let parts = [3_610.0, 3_610.0, 3_610.0].map {
            Money.rounded(Money.amount(activeSeconds: $0, hourlyRate: 45), currency: .chf)
        }
        XCTAssertEqual(Money.total(parts), Decimal(string: "135.36"))
    }
}
