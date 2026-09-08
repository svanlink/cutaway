import XCTest
@testable import Cutaway

/// The 2026-09-08 hardening pass. Every test here is a bug that shipped this
/// morning and was found by an adversarial read — not by the tests written
/// alongside the code, which is the weakest review there is.
@MainActor
final class HardeningTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))!
    }

    private func project(_ mode: BillingMode = .hourly, rate: Double = 100,
                         budget: Double = 0) throws -> Project {
        try store.createProject(name: "Maisons", client: "Richemont", mode: mode,
                                hourlyRate: rate, budget: budget, currency: .chf)
    }

    private func issue(_ p: Project, from: Int, to: Int) throws -> Invoice {
        try store.issueInvoice(for: p, from: at(from, 0), to: at(to, 0), taxMode: .notRegistered,
                               supplier: "S\nZürich", supplierVATNumber: "",
                               clientBlock: "C", now: at(to, 12), calendar: cal)
    }

    /// A day that is PARTLY invoiced must bill only what is left. It billed
    /// the whole day again: two hours invoiced plus one added later produced
    /// a line for three.
    func testAPartlyInvoicedDayBillsOnlyTheRest() throws {
        let p = try project()
        try store.record(SessionRecord(start: at(4, 9), end: at(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        _ = try issue(p, from: 1, to: 30)

        try store.record(SessionRecord(start: at(4, 14), end: at(4, 15), activeSeconds: 3600),
                         to: p, calendar: cal)
        let second = try issue(p, from: 1, to: 30)

        XCTAssertEqual(second.subtotal, Decimal(string: "100.00"),
                       "one unbilled hour, not the whole day again")
    }

    /// A fixed budget is a ceiling on the JOB, not on each invoice.
    func testABudgetIsNotAvailableTwice() throws {
        let p = try project(.budget, rate: 100, budget: 1000)
        for day in [2, 3] {
            try store.record(SessionRecord(start: at(day, 9), end: at(day, 17),
                                           activeSeconds: 8 * 3600), to: p, calendar: cal)
        }
        let first = try issue(p, from: 2, to: 2)
        let second = try issue(p, from: 3, to: 3)
        XCTAssertEqual(first.subtotal + second.subtotal, Decimal(string: "1000.00"),
                       "CHF 1'000 agreed, CHF 1'000 billed — not 2'000")
    }

    /// Moving a session corrects WHEN, never how much. Setting active time to
    /// the new span invented CHF 180 on a single sideways drag.
    func testMovingASessionCannotInventTime() throws {
        let p = try project(rate: 120)
        // Four hours on the clock, two and a half actually worked.
        try store.record(SessionRecord(start: at(4, 13), end: at(4, 17), activeSeconds: 9000),
                         to: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]

        try store.updateSession(session, from: at(4, 13, 5), to: at(4, 17, 5), calendar: cal)
        XCTAssertEqual(session.activeSeconds, 9000, accuracy: 1,
                       "a move changes when, not how much")
    }

    /// Trimming scales the worked time with the span, and never above it.
    func testTrimmingScalesTheWorkedTime() throws {
        let p = try project()
        try store.record(SessionRecord(start: at(4, 13), end: at(4, 17), activeSeconds: 9000),
                         to: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]
        try store.updateSession(session, from: at(4, 13), to: at(4, 15), calendar: cal)
        XCTAssertEqual(session.activeSeconds, 4500, accuracy: 1, "half the span, half the work")
        XCTAssertLessThanOrEqual(session.activeSeconds, 7200, "never more than the span")
    }

    /// Undo must not unlock work an invoice claims.
    func testUndoCannotUnlockAnInvoicedDay() throws {
        let p = try project()
        try store.record(SessionRecord(start: at(4, 9), end: at(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let before = store.dayEdit(at(4, 0), for: p, named: "Edit", calendar: cal)
        _ = try issue(p, from: 1, to: 30)

        XCTAssertThrowsError(try store.restore(before, for: p, calendar: cal),
                             "an issued invoice outranks an undo")
        XCTAssertEqual(store.unbilledTotal(for: p), 0, "and the work stays locked")
    }

    /// A snapshot carries identity and the lock, or restoring orphans the
    /// invoice's provenance.
    func testASnapshotCarriesIdentityAndTheLock() throws {
        let p = try project()
        try store.record(SessionRecord(start: at(4, 9), end: at(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]
        session.ensureUID()
        let snapshot = store.dayEdit(at(4, 0), for: p, named: "Edit", calendar: cal)
        XCTAssertEqual(snapshot.sessions.first?.uid, session.uid)
    }

    /// Deleting a project must not cascade over work an invoice claims.
    func testDeletingAProjectWithAnInvoiceIsRefused() throws {
        let p = try project()
        try store.record(SessionRecord(start: at(4, 9), end: at(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        let invoice = try issue(p, from: 1, to: 30)
        XCTAssertThrowsError(try store.delete(p, reassignTo: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains(invoice.number))
        }
    }

    /// The printed quantity must multiply back to the printed amount.
    func testTheRowMultipliesBackToItsAmount() throws {
        let p = try project(rate: 120)
        // 8 h 40 m 33 s — the seconds beyond the minute are given away.
        try store.record(SessionRecord(start: at(4, 9), end: at(4, 18),
                                       activeSeconds: 8 * 3600 + 40 * 60 + 33),
                         to: p, calendar: cal)
        let invoice = try issue(p, from: 1, to: 30)
        let line = try XCTUnwrap(invoice.orderedLines.first)

        XCTAssertEqual(InvoiceDocumentView.clockHours(line.quantity), "8:40")
        // What a client does with a calculator: 8 + 40/60 hours at 120.
        let byHand = Money.rounded(Money.decimal(8 + 40.0 / 60) * 120, currency: .chf)
        XCTAssertEqual(line.amount, byHand, "the page has to add up")
    }

    /// Preferences are quarantined from the test host, which IS the app.
    func testTestsCannotWriteToTheOwnersPreferences() {
        XCTAssertEqual(PrefsPolicy.suiteName(scenario: false, dataDir: nil, isTestRun: true),
                       "com.vaneickelen.cutaway.tests")
        XCTAssertNotEqual(Prefs, UserDefaults.standard,
                          "a test run must never touch the live app's defaults")
    }
}

/// The QR-bill address, built from what the invoice actually prints.
final class QRAddressTests: XCTestCase {

    func testASwissBlockParsesIntoStructuredFields() throws {
        let a = try XCTUnwrap(SwissQRBill.address(
            name: "Sebastian van Eickelen",
            block: "Sebastian van Eickelen\nBadenerstrasse 12\n8004 Zürich"))
        XCTAssertEqual(a.street, "Badenerstrasse")
        XCTAssertEqual(a.buildingNumber, "12")
        XCTAssertEqual(a.postalCode, "8004")
        XCTAssertEqual(a.town, "Zürich")
    }

    /// An address the scheme would reject produces NO payment part, rather
    /// than a bill that looks right and cannot be paid.
    func testAnUnparseableAddressRefusesRatherThanGuessing() {
        XCTAssertNil(SwissQRBill.address(name: "S", block: "S\nsomewhere"))
        XCTAssertNil(SwissQRBill.address(name: "S", block: "S"))
        XCTAssertNil(SwissQRBill.address(name: "", block: "S\nStreet 1\n8004 Zürich"))
    }

    func testTheParsedAddressFillsThePayloadPositions() throws {
        let creditor = try XCTUnwrap(SwissQRBill.address(
            name: "Sebastian", block: "Sebastian\nBadenerstrasse 12\n8004 Zürich"))
        let payload = try SwissQRBill.payload(
            iban: "CH9300762011623852957", creditor: creditor, amount: 10, currency: .chf,
            debtor: nil, referenceType: .scor, reference: "RF18539007547034", message: "")
        let lines = payload.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[6], "Badenerstrasse", "street in its own field")
        XCTAssertEqual(lines[7], "12")
        XCTAssertEqual(lines[8], "8004", "postal code is mandatory and was empty")
        XCTAssertEqual(lines[9], "Zürich")
    }
}

/// Research sustains work that is still in progress. With every workflow app
/// closed, there is no work in progress.
///
/// Observed 2026-09-08: Resolve was quit at 16:37 and the clock kept running
/// until 16:44 — recording against Claude and then Safari, because the
/// twenty-minute research window was still open. From the owner's chair that
/// is the app billing an evening of reading as editing.
final class ResearchWindowNeedsAnAnchorTests: XCTestCase {

    private func input(frontmost: String, windowOpen: Bool, anchorRunning: Bool) -> DetectionInput {
        DetectionInput(frontmostBundleID: frontmost,
                       secondsSinceInput: 0,
                       idleThreshold: 120,
                       manuallyPaused: false,
                       isAsleep: false,
                       hasActiveProject: true,
                       workAppPrefixes: DetectionInput.defaultWorkAppPrefixes,
                       anchorAppRunning: anchorRunning,
                       satellitePrefixes: DetectionInput.defaultSatellitePrefixes,
                       satelliteWindowOpen: windowOpen)
    }

    func testABrowserSustainsNothingOnceEveryWorkflowAppIsClosed() {
        let state = DetectionState.evaluate(
            input(frontmost: "com.apple.Safari", windowOpen: true, anchorRunning: false))
        XCTAssertEqual(state, .paused(.notFrontmost),
                       "Resolve closed, After Effects closed — a browser is just a browser")
    }

    /// The window still works while a workflow app is open behind it: looking
    /// something up mid-edit is the case it exists for.
    func testABrowserStillSustainsWhileAWorkflowAppIsOpen() {
        let state = DetectionState.evaluate(
            input(frontmost: "com.apple.Safari", windowOpen: true, anchorRunning: true))
        XCTAssertEqual(state, .recording)
    }

    /// An anchor in front records whether or not anything else is open — it
    /// IS the work.
    func testAnAnchorInFrontIsAlwaysWork() {
        let state = DetectionState.evaluate(
            input(frontmost: DetectionInput.resolveBundleIDs[0], windowOpen: false, anchorRunning: true))
        XCTAssertEqual(state, .recording)
    }

    /// And a closed window is still closed, whatever is running.
    func testAClosedWindowIsStillClosed() {
        let state = DetectionState.evaluate(
            input(frontmost: "com.apple.Safari", windowOpen: false, anchorRunning: true))
        XCTAssertEqual(state, .paused(.notFrontmost))
    }
}
