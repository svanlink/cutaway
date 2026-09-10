import XCTest
@testable import Cutaway

/// Unbilled / issued / paid / void — the states that stop an editor from
/// billing the same week twice or forgetting a period entirely, which the
/// research found is the real "how much do I charge" failure, not measurement.
@MainActor
final class BillingStatusTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func day(_ d: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 9))!
    }

    private func projectWithTwoDays() throws -> Project {
        let p = try store.createProject(name: "Atelier", client: "Aurora",
                                        mode: .hourly, hourlyRate: 100, currency: .chf)
        for d in [3, 4] {
            try store.record(SessionRecord(start: day(d), end: day(d).addingTimeInterval(3600),
                                           activeSeconds: 3600), to: p, calendar: cal)
        }
        return p
    }

    private func issue(_ p: Project, from: Int, to: Int) throws -> Invoice {
        try store.issueInvoice(for: p, from: day(from), to: day(to), taxMode: .notRegistered,
                               supplier: "S\nZürich", supplierVATNumber: "",
                               clientBlock: p.clientBlock, now: day(to), calendar: cal)
    }

    func testUnbilledFallsAsWorkIsInvoiced() throws {
        let p = try projectWithTwoDays()
        XCTAssertEqual(try store.unbilledTotal(for: p), Decimal(string: "200.00"))
        _ = try issue(p, from: 3, to: 3)
        XCTAssertEqual(try store.unbilledTotal(for: p), Decimal(string: "100.00"),
                       "only the invoiced day leaves the unbilled figure")
    }

    /// The same week must not bill twice — the top complaint in the research.
    func testASecondInvoiceOverTheSamePeriodFindsNothing() throws {
        let p = try projectWithTwoDays()
        _ = try issue(p, from: 1, to: 30)
        XCTAssertThrowsError(try issue(p, from: 1, to: 30)) { error in
            // Interpolating an Error prints the CASE NAME; the sentence a
            // person reads is localizedDescription.
            XCTAssertTrue(error.localizedDescription.contains("no unbilled work"),
                          "got: \(error.localizedDescription)")
        }
    }

    /// New work inside an invoiced period bills NEXT period rather than being
    /// folded silently into a document already sent.
    func testWorkAddedAfterIssuingStaysBillable() throws {
        let p = try projectWithTwoDays()
        _ = try issue(p, from: 1, to: 30)
        XCTAssertEqual(try store.unbilledTotal(for: p), 0)
        try store.record(SessionRecord(start: day(5), end: day(5).addingTimeInterval(1800),
                                       activeSeconds: 1800), to: p, calendar: cal)
        XCTAssertEqual(try store.unbilledTotal(for: p), Decimal(string: "50.00"),
                       "it bills next time, never into a document the client already holds")
    }

    func testAnInvoicedDayIsLockedAndSaysWhichInvoice() throws {
        let p = try projectWithTwoDays()
        let invoice = try issue(p, from: 3, to: 3)
        XCTAssertEqual(store.invoiceNumber(coveringDay: day(3), for: p), invoice.number)
        XCTAssertNil(store.invoiceNumber(coveringDay: day(4), for: p))
        XCTAssertThrowsError(try store.setActiveSeconds(7200, on: day(3), for: p, calendar: cal)) { error in
            XCTAssertTrue(error.localizedDescription.contains(invoice.number),
                          "the refusal names the invoice: \(error.localizedDescription)")
        }
    }

    func testMarkingPaidOnlyMovesAnIssuedInvoice() throws {
        let p = try projectWithTwoDays()
        let invoice = try issue(p, from: 1, to: 30)
        try store.markPaid(invoice)
        XCTAssertEqual(invoice.status, .paid)
        try store.voidInvoice(invoice)
        try store.markPaid(invoice)
        XCTAssertEqual(invoice.status, .void, "a voided invoice cannot be marked paid")
    }

    /// Void keeps the number — the sequence stays gapless — releases the
    /// work, and the next invoice never reuses it.
    func testVoidReleasesTheWorkAndKeepsTheNumber() throws {
        let p = try projectWithTwoDays()
        let first = try issue(p, from: 1, to: 30)
        try store.voidInvoice(first)

        XCTAssertEqual(first.status, .void)
        XCTAssertEqual(first.number.isEmpty, false)
        XCTAssertEqual(try store.unbilledTotal(for: p), Decimal(string: "200.00"), "billable again")
        XCTAssertNil(store.invoiceNumber(coveringDay: day(3), for: p), "and editable again")
        XCTAssertNoThrow(try store.setActiveSeconds(7200, on: day(3), for: p, calendar: cal))

        let second = try issue(p, from: 1, to: 30)
        XCTAssertNotEqual(second.number, first.number, "a voided number is never reused")
    }
}
