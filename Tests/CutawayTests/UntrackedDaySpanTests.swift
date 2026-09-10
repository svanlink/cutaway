import XCTest
@testable import Cutaway

/// "I worked 09:30 to 19:00 on Tuesday" — on a Tuesday Cutaway never saw.
///
/// The store could always do this; `addSession` takes any two dates. What was
/// missing was a route. `dayTotals` groups the sessions that EXIST, so a day
/// with nothing tracked produced no row; `Add session…` lived only inside an
/// expanded row; therefore the sheet that records a span was unreachable for
/// exactly the day most likely to need one. The correction took two passes:
/// invent a day total to conjure a row, expand it, add the real session, then
/// reconcile the total against the span.
///
/// These pin the behaviour the route now exposes.
@MainActor
final class UntrackedDaySpanTests: XCTestCase {

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

    func testASpanCanBeRecordedOnADayThatHasNothing() throws {
        let p = try store.createProject(name: "Maisons", client: "Richemont", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        XCTAssertTrue(store.sessions(for: p, on: at(8, 0), calendar: cal).isEmpty,
                      "Tuesday starts with nothing tracked — the case that had no route")

        try store.addSession(from: at(8, 9, 30), to: at(8, 19), for: p, calendar: cal)

        let sessions = store.sessions(for: p, on: at(8, 0), calendar: cal)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].start, at(8, 9, 30), "the span says WHEN, which a total cannot")
        XCTAssertEqual(sessions[0].end, at(8, 19))
        XCTAssertEqual(sessions[0].activeSeconds, 9.5 * 3600, accuracy: 1)
        XCTAssertTrue(sessions[0].isAdjusted, "typed time stays marked as typed, on the day and the invoice")
    }

    /// And the day now exists in the ledger, so everything else — the strip,
    /// the invoice line, the CSV row — has something to show.
    func testTheDayThenAppearsInTheBreakdown() throws {
        let p = try store.createProject(name: "Maisons", client: "Richemont", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        XCTAssertNil(store.dayTotals(for: p, calendar: cal).first { cal.isDate($0.day, inSameDayAs: at(8, 0)) },
                     "no row before — this is why the sheet was unreachable")

        try store.addSession(from: at(8, 9, 30), to: at(8, 19), for: p, calendar: cal)

        let day = try XCTUnwrap(store.dayTotals(for: p, calendar: cal)
            .first { cal.isDate($0.day, inSameDayAs: at(8, 0)) })
        XCTAssertEqual(day.activeSeconds, 9.5 * 3600, accuracy: 1)
        XCTAssertEqual(day.firstStart, at(8, 9, 30))
        XCTAssertEqual(day.lastEnd, at(8, 19))
    }

    /// The overlap guard still applies from this route: a span added to an
    /// untracked day is fine, a second one over the top of it is not.
    func testTheOverlapGuardStillHoldsFromTheNewRoute() throws {
        let p = try store.createProject(name: "Maisons", client: "Richemont", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        try store.addSession(from: at(8, 9, 30), to: at(8, 19), for: p, calendar: cal)
        XCTAssertThrowsError(try store.addSession(from: at(8, 14), to: at(8, 16), for: p, calendar: cal),
                             "an untracked day is not a licence to double-bill it")
    }
}
