import XCTest
import SwiftData
@testable import Cutaway

/// The Daily Breakdown row is a claim; the unfolded session list is the
/// itemisation behind it. If the parts don't add up to the total, the CSV
/// the client receives and the UI the editor trusts disagree.
@MainActor
final class SessionDetailTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// The fixture: two sessions on the 17th, one on the 16th.
    private func seed() throws -> Project {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        try store.record(SessionRecord(start: date(2026, 7, 17, 13), end: date(2026, 7, 17, 14, 32),
                                       activeSeconds: 47 * 60), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(2026, 7, 17, 9), end: date(2026, 7, 17, 11),
                                       activeSeconds: 5400), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(2026, 7, 16, 15), end: date(2026, 7, 16, 18),
                                       activeSeconds: 9000), to: p, calendar: cal)
        return p
    }

    func testSessionsForADayAreThatDayOnly() throws {
        let p = try seed()
        let rows = store.sessions(for: p, on: date(2026, 7, 17, 0), calendar: cal)
        XCTAssertEqual(rows.count, 2, "the 16th must not leak into the 17th")
        XCTAssertEqual(rows.map(\.activeSeconds), [5400, 47 * 60], "worked order, earliest first")
    }

    func testDetailRowsSumToTheDayTotal() throws {
        let p = try seed()
        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal)
            .first { cal.isDate($0.day, inSameDayAs: date(2026, 7, 17, 0)) })
        let sum = store.sessions(for: p, on: day.day, calendar: cal)
            .reduce(0) { $0 + $1.activeSeconds }
        XCTAssertEqual(sum, day.activeSeconds, "itemisation must reconcile with the claim")
        XCTAssertEqual(day.sessionCount, store.sessions(for: p, on: day.day, calendar: cal).count)
    }

    func testMidnightSplitItemisesUnderTheDayItWasWorked() throws {
        let p = try store.createProject(name: "Night", client: "", mode: .hourly,
                                        hourlyRate: 100, currency: .chf)
        try store.record(SessionRecord(start: date(2026, 7, 17, 22), end: date(2026, 7, 18, 2),
                                       activeSeconds: 4 * 3600), to: p, calendar: cal)
        let before = store.sessions(for: p, on: date(2026, 7, 17, 0), calendar: cal)
        let after = store.sessions(for: p, on: date(2026, 7, 18, 0), calendar: cal)
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(after.count, 1, "the split half belongs to the day it ran into")
        XCTAssertEqual(before[0].activeSeconds + after[0].activeSeconds, 4 * 3600)
    }

    func testEmptyDayHasNothingToItemise() throws {
        let p = try seed()
        XCTAssertTrue(store.sessions(for: p, on: date(2026, 7, 15, 0), calendar: cal).isEmpty)
    }

    func testDetailLineMatchesTheStoredSession() throws {
        let p = try seed()
        let s = try XCTUnwrap(store.sessions(for: p, on: date(2026, 7, 17, 0), calendar: cal).last)
        XCTAssertEqual(AppModel.sessionTimeRange(start: s.start, end: s.end),
                       "\(s.start.formatted(.dateTime.hour().minute())) – \(s.end.formatted(.dateTime.hour().minute()))")
        XCTAssertEqual(BillingEngine.earnings(activeSeconds: s.activeSeconds, hourlyRate: p.hourlyRate),
                       47.0 / 60 * 100, accuracy: 0.0001, "47 min at 100/h")
    }
}
