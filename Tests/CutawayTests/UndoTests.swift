import XCTest
import SwiftData
@testable import Cutaway

/// Shrinking a day deletes real sessions. Until 2026-09-08 that was
/// unrecoverable — the day editor could destroy tracked work with no way
/// back, in the one surface whose whole job is correcting money.
@MainActor
final class UndoTests: XCTestCase {

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

    func testAShrunkDayCanBePutBackExactly() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 11), activeSeconds: 7200),
                         to: p, calendar: cal)
        try store.record(SessionRecord(start: date(4, 14), end: date(4, 16), activeSeconds: 7200),
                         to: p, calendar: cal)
        let before = store.dayEdit(date(4, 12), for: p, named: "Edit 4 September", calendar: cal)
        XCTAssertEqual(before.sessions.count, 2)

        // Shrink the day to one hour: the newest session is destroyed.
        try store.setActiveSeconds(3600, on: date(4, 12), for: p, calendar: cal)
        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).first?.activeSeconds, 3600)

        try store.restore(before, for: p, calendar: cal)
        let after = store.dayEdit(date(4, 12), for: p, named: "x", calendar: cal)
        XCTAssertEqual(after.sessions.count, 2, "both sessions are back")
        XCTAssertEqual(after.sessions.map(\.activeSeconds), [7200, 7200])
        XCTAssertEqual(after.sessions.map(\.start), before.sessions.map(\.start),
                       "restored to the same wall-clock spans, so the CSV still tells the truth")
        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).first?.activeSeconds, 14_400)
    }

    func testRestoringLeavesOtherDaysAlone() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        try store.record(SessionRecord(start: date(3, 9), end: date(3, 10), activeSeconds: 3600),
                         to: p, calendar: cal)
        try store.record(SessionRecord(start: date(4, 9), end: date(4, 10), activeSeconds: 3600),
                         to: p, calendar: cal)
        let before = store.dayEdit(date(4, 12), for: p, named: "Edit", calendar: cal)
        try store.setActiveSeconds(0, on: date(4, 12), for: p, calendar: cal)
        try store.restore(before, for: p, calendar: cal)

        let days = store.dayTotals(for: p, calendar: cal)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.map(\.activeSeconds), [3600, 3600])
    }

    /// An adjustment is restored as an adjustment: the pencil and the
    /// `adjusted_hours` column must survive an undo.
    func testTheAdjustedFlagSurvives() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        try store.setActiveSeconds(3600, on: date(4, 12), for: p, calendar: cal)
        let before = store.dayEdit(date(4, 12), for: p, named: "Edit", calendar: cal)
        XCTAssertEqual(before.sessions.filter(\.isAdjusted).count, 1)

        try store.setActiveSeconds(0, on: date(4, 12), for: p, calendar: cal)
        try store.restore(before, for: p, calendar: cal)
        let after = store.dayEdit(date(4, 12), for: p, named: "x", calendar: cal)
        XCTAssertEqual(after.sessions.filter(\.isAdjusted).count, 1, "typed time stays marked as typed")
    }
}
