import XCTest
import SwiftData
@testable import Cutaway

/// An invoice is a document, not a query. These are the properties that buys,
/// each named by the 2026-09-07 arbitration.
@MainActor
final class InvoiceSnapshotTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    private func project(rate: Double = 90, mode: BillingMode = .hourly,
                         budget: Double = 0) throws -> Project {
        try store.createProject(name: "Aurora", client: "Aurora EC", mode: mode,
                                hourlyRate: rate, budget: budget, currency: .chf)
    }

    private func issue(_ p: Project, from: Int = 1, to: Int = 30,
                       taxMode: TaxMode = .notRegistered) throws -> Invoice {
        try store.issueInvoice(for: p, from: date(from, 12), to: date(to, 12),
                               taxMode: taxMode, supplier: "Sebastian", supplierVATNumber: "",
                               clientBlock: "Aurora EC", now: date(30, 12), calendar: cal)
    }

    /// The property the whole snapshot design exists for.
    func testAnIssuedTotalSurvivesARateChange() throws {
        let p = try project(rate: 90)
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 13), activeSeconds: 14_400),
                         to: p, calendar: cal)
        let invoice = try issue(p)
        XCTAssertEqual(invoice.total, Decimal(string: "360.00"))

        p.hourlyRate = 200
        try store.context.save()
        XCTAssertEqual(invoice.total, Decimal(string: "360.00"),
                       "a document a client holds does not change because a rate did")
        XCTAssertEqual(invoice.orderedLines.first?.unitPrice, Decimal(string: "90.000000"))
    }

    /// A day is a local-calendar fact; the document records which calendar.
    func testTheIssuedTotalIsTimeZoneIndependent() throws {
        let p = try project(rate: 90)
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let invoice = try issue(p)
        XCTAssertEqual(invoice.timeZoneIdentifier, "Europe/Zurich")
        XCTAssertEqual(invoice.total, Decimal(string: "180.00"))

        // Reading it in Bogotá does not regroup anything: the figures are copies.
        var bogota = Calendar(identifier: .gregorian)
        bogota.timeZone = TimeZone(identifier: "America/Bogota")!
        XCTAssertEqual(invoice.total, Decimal(string: "180.00"))
        XCTAssertEqual(invoice.lines.count, 1)
    }

    func testVoidKeepsTheNumberAndReleasesTheWork() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let invoice = try issue(p)
        XCTAssertTrue(p.sessions.allSatisfy(\.isInvoiced))

        try store.voidInvoice(invoice)
        XCTAssertEqual(invoice.status, .void)
        XCTAssertEqual(invoice.number, "INV-2026-0001", "the number is kept, so the sequence has no hole")
        XCTAssertTrue(p.sessions.allSatisfy { !$0.isInvoiced }, "the work is billable again")
    }

    func testAReissueNeverReusesAVoidedNumber() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let first = try issue(p)
        try store.voidInvoice(first)
        let second = try issue(p)
        XCTAssertEqual(first.number, "INV-2026-0001")
        XCTAssertEqual(second.number, "INV-2026-0002", "a voided number is spent, not recycled")
    }

    func testEveryLineTracesToItsSessions() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        try store.record(SessionRecord(start: date(4, 14), end: date(4, 15), activeSeconds: 3600),
                         to: p, calendar: cal)
        try store.record(SessionRecord(start: date(5, 9), end: date(5, 10), activeSeconds: 3600),
                         to: p, calendar: cal)
        let invoice = try issue(p)

        let claimed = invoice.lines.flatMap(\.sessionUIDs)
        let actual = p.sessions.map(\.uid).filter { !$0.isEmpty }
        XCTAssertEqual(Set(claimed), Set(actual), "no session is orphaned by the document")
        XCTAssertEqual(claimed.count, Set(claimed).count, "and none is claimed twice")
        XCTAssertEqual(invoice.lines.count, 2, "one line per worked day")
        XCTAssertEqual(invoice.orderedLines.first?.sessionUIDs.count, 2,
                       "the FIRST printed day carries both of its sessions")
        XCTAssertEqual(invoice.orderedLines.map(\.day), [date(4, 12), date(5, 12)].map { cal.startOfDay(for: $0) },
                       "and the document is in date order")
    }

    /// Typed time may be carried; it may not be hidden.
    func testTypedTimeReachesTheDocumentAsTyped() throws {
        let p = try project(rate: 90)
        try store.setActiveSeconds(3600, on: date(4, 12), for: p, calendar: cal)
        let invoice = try issue(p)
        XCTAssertEqual(invoice.adjustedHours, Decimal(string: "1.0000"))
        XCTAssertEqual(invoice.total, Decimal(string: "90.00"))
    }

    func testWorkAlreadyInvoicedIsNeverBilledTwice() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        _ = try issue(p)
        // New work inside the same period bills NEXT time, unlocked.
        try store.record(SessionRecord(start: date(5, 9), end: date(5, 10), activeSeconds: 3600),
                         to: p, calendar: cal)
        let second = try issue(p)
        XCTAssertEqual(second.lines.count, 1)
        XCTAssertEqual(second.total, Decimal(string: "90.00"), "only the new day")
    }

    func testAnInvoicedDayRefusesToBeEdited() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        _ = try issue(p)
        XCTAssertThrowsError(try store.setActiveSeconds(3600, on: date(4, 12), for: p, calendar: cal)) { error in
            guard case SessionStore.InvoiceError.dayIsInvoiced(let number) = error else {
                return XCTFail("expected a refusal naming the invoice, got \(error)")
            }
            XCTAssertEqual(number, "INV-2026-0001")
        }
        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).first?.activeSeconds, 7200,
                       "and nothing changed")
    }

    func testDeletingInvoicedWorkIsRefusedByNumber() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        _ = try issue(p)
        XCTAssertThrowsError(try store.assertNothingInvoiced(in: p))
    }

    /// A fixed price is a ceiling. 48 h × 120 is 5'760; the budget is 4'500.
    func testABudgetProjectBillsTheBudgetNotTheOverrun() throws {
        let p = try project(rate: 120, mode: .budget, budget: 4_500)
        for day in 1...6 {
            try store.record(SessionRecord(start: date(day, 8), end: date(day, 16), activeSeconds: 28_800),
                             to: p, calendar: cal)
        }
        let invoice = try issue(p)
        XCTAssertEqual(invoice.subtotal, Decimal(string: "4500.00"),
                       "the agreed price, not the accrued time")
        XCTAssertTrue(invoice.lines.contains { $0.kind == .manual },
                      "and the difference is a visible line, not a silent trim")
    }

    /// A fixed price is a ceiling that stays a ceiling.
    ///
    /// budgetCapped guards `budget > 0`, and the store passes it what is
    /// LEFT of the budget. Once the budget is fully invoiced that remainder
    /// is zero, the guard fails, and the draft comes back UNCAPPED — so the
    /// second invoice bills hourly time against a job the client agreed a
    /// fixed price for, with no cap, no warning and no mention that it is a
    /// fixed-price project.
    func testAFullyInvoicedBudgetRefusesToBillMore() throws {
        let p = try project(rate: 150, mode: .budget, budget: 4_500)
        for day in 1...6 {
            try store.record(SessionRecord(start: date(day, 8), end: date(day, 16), activeSeconds: 28_800),
                             to: p, calendar: cal)
        }
        let first = try issue(p, from: 1, to: 6)
        XCTAssertEqual(first.subtotal, Decimal(string: "4500.00"))

        // Revisions the following week, on a job that is fully paid for.
        try store.record(SessionRecord(start: date(15, 9), end: date(15, 15), activeSeconds: 21_600),
                         to: p, calendar: cal)
        XCTAssertThrowsError(try issue(p, from: 15, to: 20),
                             "the budget is spent — this must not quietly bill 900 on top") { error in
            guard case SessionStore.InvoiceError.budgetFullyInvoiced = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    /// Renaming a project must not hand back a budget that is already spent.
    ///
    /// invoicedTotal joined issued invoices to the project by NAME, and a
    /// rename mutates that name in place — so every invoice already issued
    /// became invisible to the cap and the ceiling reset to full. A client
    /// rebrand, or tidying a Resolve project name, doubled the job.
    func testRenamingAProjectDoesNotResetItsBudget() throws {
        let p = try project(rate: 150, mode: .budget, budget: 4_500)
        for day in 1...6 {
            try store.record(SessionRecord(start: date(day, 8), end: date(day, 16), activeSeconds: 28_800),
                             to: p, calendar: cal)
        }
        _ = try issue(p, from: 1, to: 6)
        try store.rename(p, to: "Aurora EC — Atelier 2026")

        try store.record(SessionRecord(start: date(15, 9), end: date(15, 15), activeSeconds: 21_600),
                         to: p, calendar: cal)
        XCTAssertThrowsError(try issue(p, from: 15, to: 20),
                             "the 4'500 already billed still counts after a rename") { error in
            guard case SessionStore.InvoiceError.budgetFullyInvoiced = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testSwissVATIsRefusedWithoutAUID() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        XCTAssertThrowsError(try store.issueInvoice(
            for: p, from: date(1, 12), to: date(30, 12), taxMode: .swissVAT,
            supplier: "Sebastian", supplierVATNumber: "", clientBlock: "Aurora",
            now: date(30, 12), calendar: cal))
        XCTAssertTrue(p.sessions.allSatisfy { !$0.isInvoiced },
                      "a refused issue locks nothing")
    }

    /// MWSTG Art. 27: state a tax and you owe it, registered or not.
    func testAnUnregisteredInvoiceCannotStateATax() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let invoice = try issue(p, taxMode: .notRegistered)
        XCTAssertEqual(invoice.taxAmount, 0)
        XCTAssertEqual(invoice.taxRate, 0)
        XCTAssertEqual(invoice.total, invoice.subtotal)
        XCTAssertFalse(invoice.taxMode.showsTaxLine)
    }

    func testReverseChargeAddsNoTaxButSaysWhy() throws {
        XCTAssertFalse(TaxMode.euReverseCharge.showsTaxLine)
        XCTAssertTrue(TaxMode.euReverseCharge.note.contains("Reverse charge"))
        XCTAssertEqual(TaxMode.swissVAT.rate, 8.1)
    }

    func testUnbilledTotalCountsOnlyUnlockedWork() throws {
        let p = try project(rate: 90)
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        XCTAssertEqual(store.unbilledTotal(for: p), Decimal(string: "180.00"))
        _ = try issue(p)
        XCTAssertEqual(store.unbilledTotal(for: p), 0, "invoiced work is no longer owed to you")
    }
}
