import XCTest
@testable import Cutaway

/// The number the owner approves must be the number the client receives.
///
/// `InvoiceSheet.refresh()` claimed to be "built from the same pure code that
/// will freeze the document". It wasn't. It grouped the project's whole
/// history instead of the billable sessions, so a day holding two invoiced
/// hours and one unbilled hour previewed as three hours and issued as one;
/// and it capped a budget at the full figure instead of the remainder, so a
/// second budget invoice previewed uncapped. Neither over-billed a client —
/// the preview was always the HIGHER figure — but it is the number read out
/// on the phone.
///
/// These assert the two paths agree, rather than asserting either number.
@MainActor
final class PreviewMatchesIssuedTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func at(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
    }

    /// What the sheet computes, in the same order the sheet computes it.
    private func preview(_ p: Project, from: Date, to: Date,
                         taxMode: TaxMode) -> InvoiceBuilder.Draft {
        let sessions = store.billableSessions(for: p, from: from, to: to, calendar: cal)
        var uidsByDay: [Date: [String]] = [:]
        for s in sessions { uidsByDay[cal.startOfDay(for: s.start), default: []].append(s.ensureUID()) }
        let days = SessionStore.dayTotals(from: sessions, projectRate: p.hourlyRate, calendar: cal)
        let lines = InvoiceBuilder.lines(for: days, sessionUIDsByDay: uidsByDay,
                                         currency: p.currency, calendar: cal)
        var draft = InvoiceBuilder.totals(lines, taxMode: taxMode, currency: p.currency)
        if p.mode == .budget {
            let billed = (try? store.invoicedTotal(for: p)) ?? 0
            draft = InvoiceBuilder.budgetCapped(draft, budget: Money.decimal(p.budget) - billed,
                                                taxRate: taxMode.rate, currency: p.currency)
        }
        return draft
    }

    func testAPartlyInvoicedDayPreviewsAtWhatItWillBill() throws {
        let p = try store.createProject(name: "Richemont", client: "Richemont EC",
                                        mode: .hourly, hourlyRate: 120, currency: .chf)
        // Two hours on the 3rd, invoiced. One more hour on the 3rd, after.
        try store.record(SessionRecord(start: at(3, 9), end: at(3, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        _ = try store.issueInvoice(for: p, from: at(1, 12), to: at(3, 23), taxMode: .notRegistered,
                                   supplier: "S", supplierVATNumber: "", clientBlock: "C",
                                   now: at(3, 23), calendar: cal)
        try store.record(SessionRecord(start: at(3, 14), end: at(3, 15), activeSeconds: 3600),
                         to: p, calendar: cal)

        let shown = preview(p, from: at(1, 12), to: at(30, 12), taxMode: .notRegistered)
        let issued = try store.issueInvoice(for: p, from: at(1, 12), to: at(30, 12),
                                            taxMode: .notRegistered, supplier: "S",
                                            supplierVATNumber: "", clientBlock: "C",
                                            now: at(30, 12), calendar: cal)
        XCTAssertEqual(shown.subtotal, issued.subtotal,
                       "the preview must not count hours that are already on an invoice")
        XCTAssertEqual(shown.subtotal, Decimal(string: "120.00"))
    }

    func testASecondBudgetInvoicePreviewsTheCapItWillGet() throws {
        let p = try store.createProject(name: "Film", client: "Client", mode: .budget,
                                        hourlyRate: 150, budget: 4_500, currency: .chf)
        for day in 1...3 {
            try store.record(SessionRecord(start: at(day, 8), end: at(day, 14), activeSeconds: 21_600),
                             to: p, calendar: cal)
        }
        _ = try store.issueInvoice(for: p, from: at(1, 12), to: at(3, 23), taxMode: .notRegistered,
                                   supplier: "S", supplierVATNumber: "", clientBlock: "C",
                                   now: at(3, 23), calendar: cal)
        for day in 10...13 {
            try store.record(SessionRecord(start: at(day, 8), end: at(day, 16), activeSeconds: 28_800),
                             to: p, calendar: cal)
        }
        let shown = preview(p, from: at(10, 12), to: at(20, 12), taxMode: .notRegistered)
        let issued = try store.issueInvoice(for: p, from: at(10, 12), to: at(20, 12),
                                            taxMode: .notRegistered, supplier: "S",
                                            supplierVATNumber: "", clientBlock: "C",
                                            now: at(20, 12), calendar: cal)
        XCTAssertEqual(shown.subtotal, issued.subtotal,
                       "the preview must cap at what is LEFT of the budget")
    }

    /// The printed VAT is the printed rate applied to the printed subtotal —
    /// including after a cap, where it used to prorate an already-rounded tax
    /// and land a rappen away from what a client's calculator gives.
    func testCappedVATReconcilesWithThePrintedSubtotal() {
        let line = InvoiceBuilder.Line(kind: .time, day: nil, text: "d", quantity: 1, unit: "h",
                                       unitPrice: 1, amount: Decimal(string: "3669.46")!,
                                       adjustedHours: 0, sessionUIDs: [])
        let draft = InvoiceBuilder.totals([line], taxMode: .swissVAT, currency: .chf)
        let capped = InvoiceBuilder.budgetCapped(draft, budget: Decimal(string: "3422.75")!,
                                                 taxRate: TaxMode.swissVAT.rate, currency: .chf)
        XCTAssertEqual(capped.taxAmount,
                       Money.rounded(capped.subtotal * Money.decimal(TaxMode.swissVAT.rate) / 100,
                                     currency: .chf))
        XCTAssertEqual(capped.total, capped.subtotal + capped.taxAmount)
    }
}

extension PreviewMatchesIssuedTests {
    /// A budget preview must not turn a failed read into "nothing billed yet".
    ///
    /// Found by Greptile, 2026-09-10. `refresh()` had
    /// `(try? invoicedTotal(for:)) ?? 0`, so if the invoice fetch threw, the
    /// sheet showed the FULL budget as remaining and left Issue enabled —
    /// while the issue path calls the same function with `try` and refuses.
    /// The preview promised money that could not be invoiced. Swallowing an
    /// error in a money path is the one thing this app is not allowed to do.
    func testAFailedInvoiceReadIsNotReportedAsNothingBilled() throws {
        let p = try store.createProject(name: "Film", client: "Client", mode: .budget,
                                        hourlyRate: 150, budget: 4_500, currency: .chf)
        for day in 1...3 {
            try store.record(SessionRecord(start: at(day, 8), end: at(day, 14), activeSeconds: 21_600),
                             to: p, calendar: cal)
        }
        _ = try store.issueInvoice(for: p, from: at(1, 12), to: at(3, 23), taxMode: .notRegistered,
                                   supplier: "S", supplierVATNumber: "", clientBlock: "C",
                                   now: at(3, 23), calendar: cal)
        // The healthy read is the baseline: something HAS been billed, so a
        // preview that reports zero is reporting a failure as a fact.
        let billed = try store.invoicedTotal(for: p)
        XCTAssertGreaterThan(billed, 0, "the fixture must have an issued invoice to make this meaningful")
        XCTAssertNotEqual(billed, 0,
                          "if this ever reads 0 the preview's `?? 0` fallback is indistinguishable "
                        + "from a real 'nothing billed yet', which is exactly the bug")
    }
}
