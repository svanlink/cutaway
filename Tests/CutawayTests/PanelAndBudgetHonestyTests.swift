import XCTest
import SwiftData
@testable import Cutaway

/// Figures the panel shows all day, and the promises they carry.
@MainActor
final class PanelAndBudgetHonestyTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: d, hour: h))!
    }

    /// A fixed price is a ceiling, so nothing above it is owed.
    ///
    /// `InvoiceBuilder.budgetCapped` has always refused to bill past the
    /// budget, but "unbilled" counted every uninvoiced hour — so a budget job
    /// worked past its price advertised money on the panel that the invoice
    /// sheet would then decline to put on a document.
    func testABudgetJobNeverShowsMoreUnbilledThanItsRemainingBudget() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .budget,
                                        hourlyRate: 100, budget: 500, currency: .chf)
        // Eight hours at 100 = 800 accrued against a 500 budget.
        try store.record(SessionRecord(start: date(3, 9), end: date(3, 17), activeSeconds: 28_800),
                         to: p, calendar: cal)

        XCTAssertEqual(try store.unbilledTotal(for: p), Decimal(string: "500.00"),
                       "the ceiling, not the accrual")
    }

    /// Once the ceiling is invoiced, nothing is owed — however much more was
    /// worked.
    func testAFullyInvoicedBudgetJobShowsNothingUnbilled() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .budget,
                                        hourlyRate: 100, budget: 500, currency: .chf)
        try store.record(SessionRecord(start: date(3, 9), end: date(3, 17), activeSeconds: 28_800),
                         to: p, calendar: cal)
        _ = try store.issueInvoice(for: p, from: date(3, 0), to: date(4, 0),
                                   taxMode: .notRegistered, supplier: "Studio\nStreet 1\n8000 Zurich",
                                   supplierVATNumber: "", clientBlock: "Client\nStreet 2\n8000 Zurich",
                                   iban: "")
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 13), activeSeconds: 14_400),
                         to: p, calendar: cal)

        XCTAssertEqual(try store.unbilledTotal(for: p), 0,
                       "the budget is spent; the overrun is a conversation, not an invoice line")
    }

    /// An hourly job is uncapped and keeps counting.
    func testAnHourlyJobIsUnaffectedByTheCap() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 100, budget: 500, currency: .chf)
        try store.record(SessionRecord(start: date(3, 9), end: date(3, 17), activeSeconds: 28_800),
                         to: p, calendar: cal)

        XCTAssertEqual(try store.unbilledTotal(for: p), Decimal(string: "800.00"))
    }

    /// A project created a minute ago has no time on it, which is a zero
    /// state — and the panel used to answer that by hiding the list of the
    /// OTHER projects, the only way to switch back to the one holding the
    /// day's work.
    func testTheZeroStateKeepsTheProjectSwitcherWhenThereIsSomewhereToSwitch() {
        let withOthers = MenuBarPanel.blocks(zeroState: true, offersAccessibility: false,
                                             workDetectedWhilePaused: false, researchLabel: false,
                                             receipt: false, hasOtherProjects: true)
        XCTAssertTrue(withOthers.contains(.projects))
        XCTAssertTrue(withOthers.contains(.zeroState), "and it still says why nothing is counting")

        let alone = MenuBarPanel.blocks(zeroState: true, offersAccessibility: false,
                                        workDetectedWhilePaused: false, researchLabel: false,
                                        receipt: false, hasOtherProjects: false)
        XCTAssertFalse(alone.contains(.projects), "one project is not a list")
    }

    /// A refused delete is not a delete.
    func testDeletingAProjectWithInvoicedWorkIsRefusedOutright() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        try store.record(SessionRecord(start: date(3, 9), end: date(3, 17), activeSeconds: 28_800),
                         to: p, calendar: cal)
        _ = try store.issueInvoice(for: p, from: date(3, 0), to: date(4, 0),
                                   taxMode: .notRegistered, supplier: "Studio\nStreet 1\n8000 Zurich",
                                   supplierVATNumber: "", clientBlock: "Client\nStreet 2\n8000 Zurich",
                                   iban: "")

        XCTAssertThrowsError(try store.delete(p, reassignTo: nil))
        XCTAssertEqual(try store.projects().count, 1, "and it is still there")
    }
}
