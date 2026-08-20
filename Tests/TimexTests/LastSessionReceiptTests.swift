import XCTest
import SwiftData
@testable import Cutaway

/// The menu-bar "Last session" line is a billing receipt: it must state what
/// the store actually holds, and it must not go stale-but-plausible when the
/// day rolls over.
@MainActor
final class LastSessionReceiptTests: XCTestCase {

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

    func testLastSessionIsTheNewestClosedSession() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        try store.record(SessionRecord(start: date(2026, 7, 17, 9), end: date(2026, 7, 17, 11),
                                       activeSeconds: 5400), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(2026, 7, 17, 13), end: date(2026, 7, 17, 14, 32),
                                       activeSeconds: 47 * 60), to: p, calendar: cal)
        try store.record(SessionRecord(start: date(2026, 7, 16, 15), end: date(2026, 7, 16, 18),
                                       activeSeconds: 9000), to: p, calendar: cal)

        let last = try XCTUnwrap(store.lastSession(for: p))
        XCTAssertEqual(last.end, date(2026, 7, 17, 14, 32), "newest END wins, not newest insert")
        XCTAssertEqual(last.activeSeconds, 47 * 60)
    }

    func testNoSessionsMeansNoReceipt() throws {
        let p = try store.createProject(name: "Empty", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        XCTAssertNil(store.lastSession(for: p), "a project with no history must claim nothing")
    }

    func testReceiptTextMatchesTheStoredSession() throws {
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        let end = date(2026, 7, 17, 14, 32)
        try store.record(SessionRecord(start: date(2026, 7, 17, 13), end: end,
                                       activeSeconds: 47 * 60), to: p, calendar: cal)
        let last = try XCTUnwrap(store.lastSession(for: p))
        let line = AppModel.lastSessionText(activeSeconds: last.activeSeconds, end: last.end,
                                            now: end, calendar: cal)
        XCTAssertTrue(line.hasPrefix("Last session: 47 min · "), "got \(line)")
        XCTAssertTrue(line.contains(end.formatted(.dateTime.hour().minute())), "got \(line)")
    }

    func testOlderSessionCarriesItsDate() {
        let end = date(2026, 7, 17, 14, 32)
        let sameDay = AppModel.lastSessionText(activeSeconds: 47 * 60, end: end,
                                               now: date(2026, 7, 17, 20), calendar: cal)
        let nextDay = AppModel.lastSessionText(activeSeconds: 47 * 60, end: end,
                                               now: date(2026, 7, 18, 9), calendar: cal)
        XCTAssertNotEqual(sameDay, nextDay, "a day-old receipt must not read as today's")
        XCTAssertTrue(nextDay.contains(end.formatted(.dateTime.month(.abbreviated).day())),
                      "got \(nextDay)")
    }

    func testHoursFormatAndMinuteRounding() {
        let end = date(2026, 7, 17, 14, 32)
        let now = date(2026, 7, 17, 20)
        XCTAssertTrue(AppModel.lastSessionText(activeSeconds: 2 * 3600 + 5 * 60, end: end,
                                               now: now, calendar: cal)
            .hasPrefix("Last session: 2:05 h · "))
        XCTAssertTrue(AppModel.lastSessionText(activeSeconds: 90, end: end, now: now, calendar: cal)
            .hasPrefix("Last session: 2 min · "), "rounds to the nearest minute")
        XCTAssertTrue(AppModel.lastSessionText(activeSeconds: 5, end: end, now: now, calendar: cal)
            .hasPrefix("Last session: 1 min · "), "never claims a 0 min session")
    }
}
