import XCTest
import SwiftData
@testable import Cutaway

/// The menu-bar panel renders a row per project on every tick. Each row asked
/// the store for that project's total today, and the store filtered the
/// project's entire session history to answer — so the cost of showing the
/// panel grew with every month the app was used successfully.
@MainActor
final class TodayCacheTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    private func project(_ name: String, days: Int, now: Date) throws -> Project {
        let p = try store.createProject(name: name, client: "", mode: .hourly,
                                        hourlyRate: 85, currency: .chf)
        for i in 0..<days {
            let start = cal.date(byAdding: .day, value: -i, to: now)!
            try store.record(SessionRecord(start: start, end: start.addingTimeInterval(3600),
                                           activeSeconds: 3600), to: p, calendar: cal)
        }
        return p
    }

    /// The defect, measured: rendering must not re-walk history.
    func testRenderingDoesNotRescaleWithHistory() throws {
        let now = date(2026, 7, 17, 14)
        let projects = try (0..<10).map { try project("P\($0)", days: 60, now: now) }

        let before = store.sessionScanCount
        // One second of panel rendering: ten rows, twice.
        for _ in 0..<2 {
            for p in projects { _ = store.activeSecondsToday(for: p, calendar: cal, now: now) }
        }
        let scans = store.sessionScanCount - before
        XCTAssertEqual(scans, 10, "one scan per project, then memoised — not one per render")
    }

    func testTheAnswerIsStillCorrect() throws {
        let now = date(2026, 7, 17, 14)
        let p = try project("P", days: 5, now: now)
        let direct = p.sessions
            .filter { cal.startOfDay(for: $0.start) == cal.startOfDay(for: now) }
            .reduce(0) { $0 + $1.activeSeconds }
        XCTAssertEqual(store.activeSecondsToday(for: p, calendar: cal, now: now), direct)
        XCTAssertEqual(store.activeSecondsToday(for: p, calendar: cal, now: now), direct,
                       "a memoised answer must equal the computed one")
    }

    /// A cache that outlives the truth is worse than no cache — this is
    /// billing data on screen.
    func testRecordingWorkInvalidatesImmediately() throws {
        let now = date(2026, 7, 17, 14)
        let p = try project("P", days: 1, now: now)
        XCTAssertEqual(store.activeSecondsToday(for: p, calendar: cal, now: now), 3600)

        try store.record(SessionRecord(start: date(2026, 7, 17, 16),
                                       end: date(2026, 7, 17, 17),
                                       activeSeconds: 1800), to: p, calendar: cal)
        XCTAssertEqual(store.activeSecondsToday(for: p, calendar: cal, now: now), 5400,
                       "the panel must show banked time the moment it is banked")
    }

    func testMidnightInvalidatesItself() throws {
        let now = date(2026, 7, 17, 14)
        let p = try project("P", days: 3, now: now)
        XCTAssertEqual(store.activeSecondsToday(for: p, calendar: cal, now: now), 3600)
        let tomorrow = date(2026, 7, 18, 9)
        XCTAssertEqual(store.activeSecondsToday(for: p, calendar: cal, now: tomorrow), 0,
                       "the day is part of the key — yesterday's total must not carry over")
    }

    func testDeletingAProjectInvalidates() throws {
        let now = date(2026, 7, 17, 14)
        let keep = try project("Keep", days: 1, now: now)
        let gone = try project("Gone", days: 1, now: now)
        _ = store.activeSecondsToday(for: keep, calendar: cal, now: now)

        try store.delete(gone, reassignTo: keep)
        XCTAssertEqual(store.activeSecondsToday(for: keep, calendar: cal, now: now), 7200,
                       "reassigned sessions must appear on the heir immediately")
    }

    func testEachProjectIsCachedSeparately() throws {
        let now = date(2026, 7, 17, 14)
        let a = try project("A", days: 1, now: now)
        let b = try project("B", days: 1, now: now)
        try store.record(SessionRecord(start: date(2026, 7, 17, 16), end: date(2026, 7, 17, 17),
                                       activeSeconds: 900), to: b, calendar: cal)
        XCTAssertEqual(store.activeSecondsToday(for: a, calendar: cal, now: now), 3600)
        XCTAssertEqual(store.activeSecondsToday(for: b, calendar: cal, now: now), 4500,
                       "one project's total must never be served for another")
    }
}
