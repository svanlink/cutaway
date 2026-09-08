import XCTest
@testable import Cutaway

/// "I worked 09:00 to 12:00" — a span, not a total. Setting a day's total
/// had to invent a moment for the hours to sit at, so a corrected day could
/// say four hours without being able to say when, and "when" is the thing a
/// client asks about.
@MainActor
final class SessionSpanTests: XCTestCase {

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

    private func project(rate: Double = 120) throws -> Project {
        try store.createProject(name: "Maisons", client: "Richemont", mode: .hourly,
                                hourlyRate: rate, currency: .chf)
    }

    func testASpanBecomesHoursAndKeepsItsClockTimes() throws {
        let p = try project()
        try store.addSession(from: at(4, 9), to: at(4, 12, 30), for: p, calendar: cal)

        let sessions = store.sessions(for: p, on: at(4, 0), calendar: cal)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].activeSeconds, 3.5 * 3600, accuracy: 0.5)
        XCTAssertEqual(sessions[0].start, at(4, 9))
        XCTAssertEqual(sessions[0].end, at(4, 12, 30))
        XCTAssertTrue(sessions[0].isAdjusted, "typed time stays marked as typed")
    }

    /// The hours follow the span. A session that says 09:00–12:00 and bills
    /// two hours is a session nobody can defend.
    func testMovingASessionMovesItsHours() throws {
        let p = try project()
        try store.addSession(from: at(4, 9), to: at(4, 12), for: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]

        try store.updateSession(session, from: at(4, 14), to: at(4, 15, 30), calendar: cal)
        XCTAssertEqual(session.activeSeconds, 1.5 * 3600, accuracy: 0.5)
        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).first?.activeSeconds ?? 0,
                       1.5 * 3600, accuracy: 0.5)
    }

    func testAnEndBeforeItsStartIsRefused() throws {
        let p = try project()
        XCTAssertThrowsError(try store.addSession(from: at(4, 12), to: at(4, 9), for: p, calendar: cal)) {
            XCTAssertTrue($0.localizedDescription.contains("after the start"))
        }
    }

    /// Adding across midnight splits deliberately, so both days stay true.
    func testAnOvernightSpanSplitsAtMidnight() throws {
        let p = try project()
        try store.addSession(from: at(4, 22), to: at(5, 1), for: p, calendar: cal)
        // dayTotals is newest-first; assert by DAY so the order of the list
        // is not silently part of the contract.
        let byDay = Dictionary(uniqueKeysWithValues: store.dayTotals(for: p, calendar: cal)
            .map { (cal.startOfDay(for: $0.day), round($0.activeSeconds)) })
        XCTAssertEqual(byDay.count, 2)
        XCTAssertEqual(byDay[cal.startOfDay(for: at(4, 0))], 2 * 3600, "22:00 to midnight")
        XCTAssertEqual(byDay[cal.startOfDay(for: at(5, 0))], 1 * 3600, "midnight to 01:00")
    }

    /// Editing across midnight would turn one row into two under the owner's
    /// hands, so it refuses and says what to do instead.
    func testEditingASessionAcrossMidnightIsRefused() throws {
        let p = try project()
        try store.addSession(from: at(4, 9), to: at(4, 12), for: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]
        XCTAssertThrowsError(try store.updateSession(session, from: at(4, 23), to: at(5, 1), calendar: cal)) {
            XCTAssertTrue($0.localizedDescription.contains("end on the day it started"))
        }
    }

    func testDeletingASessionRemovesItsMoney() throws {
        let p = try project()
        try store.addSession(from: at(4, 9), to: at(4, 12), for: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]
        try store.deleteSession(session)
        XCTAssertTrue(store.dayTotals(for: p, calendar: cal).isEmpty)
    }

    /// An invoiced day is closed to all three operations, not just to the
    /// day editor.
    func testAnInvoicedDayRefusesEverySpanEdit() throws {
        let p = try project()
        try store.addSession(from: at(4, 9), to: at(4, 12), for: p, calendar: cal)
        let session = store.sessions(for: p, on: at(4, 0), calendar: cal)[0]
        let invoice = try store.issueInvoice(for: p, from: at(1, 0), to: at(30, 0),
                                             taxMode: .notRegistered, supplier: "S\nZürich",
                                             supplierVATNumber: "", clientBlock: "C",
                                             now: at(30, 0), calendar: cal)

        XCTAssertThrowsError(try store.addSession(from: at(4, 14), to: at(4, 15), for: p, calendar: cal)) {
            XCTAssertTrue($0.localizedDescription.contains(invoice.number))
        }
        XCTAssertThrowsError(try store.updateSession(session, from: at(4, 10), to: at(4, 11), calendar: cal))
        XCTAssertThrowsError(try store.deleteSession(session))
    }

    /// Moving a session INTO an invoiced day is refused too — the guard has
    /// to look at where it lands, not only where it came from.
    func testMovingASessionIntoAnInvoicedDayIsRefused() throws {
        let p = try project()
        try store.addSession(from: at(3, 9), to: at(3, 12), for: p, calendar: cal)
        try store.addSession(from: at(9, 9), to: at(9, 12), for: p, calendar: cal)
        _ = try store.issueInvoice(for: p, from: at(1, 0), to: at(5, 0),
                                   taxMode: .notRegistered, supplier: "S\nZürich",
                                   supplierVATNumber: "", clientBlock: "C",
                                   now: at(5, 0), calendar: cal)
        let free = store.sessions(for: p, on: at(9, 0), calendar: cal)[0]
        XCTAssertThrowsError(try store.updateSession(free, from: at(3, 14), to: at(3, 15), calendar: cal),
                             "a session must not be moved onto an invoiced day")
    }
}
