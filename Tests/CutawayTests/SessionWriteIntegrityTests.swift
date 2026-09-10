import XCTest
import SwiftData
@testable import Cutaway

/// The three ways one afternoon could be billed twice, or shown as saved
/// when it was not.
///
/// All three share a root: SwiftData's `save()` can throw with the row
/// already on disk. Every write that may be retried therefore needs a stable
/// identity, and every write that may fail needs the context put back the way
/// it was found.
@MainActor
final class SessionWriteIntegrityTests: XCTestCase {

    private var store: SessionStore!
    private var cal: Calendar!

    override func setUp() async throws {
        store = try SessionStore(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    }

    private func date(_ h: Int, _ mi: Int = 0, day: Int = 3) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: h, minute: mi))!
    }

    private func project() throws -> Project {
        try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                hourlyRate: 85, currency: .chf)
    }

    /// The live path's own uid is what a journal replay matches on.
    ///
    /// The uid used to be minted inside the journal ENTRY — after the store
    /// write had already happened without one. So the landed row carried uid
    /// "", the replay matched nothing, and the same three hours were inserted
    /// a second time and invoiced twice. This asserts the property that makes
    /// a replay safe, not the line that was wrong: a record written with a
    /// uid and replayed with the same uid is one piece of work.
    func testAReplayOfAlreadyStoredWorkAddsNothing() throws {
        let p = try project()
        let record = SessionRecord(start: date(14), end: date(17), activeSeconds: 10_800)
        let uid = UUID().uuidString

        try store.record(record, to: p, uid: uid)
        try store.record(record, to: p, uid: uid, rate: 85)

        XCTAssertEqual(p.sessions.count, 1, "the afternoon exists once")
        XCTAssertEqual(store.totalActiveSeconds(for: p), 10_800, accuracy: 1)
    }

    /// Crash recovery keeps its snapshot when a persist fails and retries on
    /// the next launch, so its identity has to survive a relaunch. A fresh
    /// UUID each time did not, and billed the crashed session again.
    func testCrashRecoveryUsesTheSameIdentityOnEveryRelaunch() throws {
        let p = try project()
        let record = SessionRecord(start: date(9), end: date(12), activeSeconds: 10_800)

        // The identity `persistRecovered` derives, twice — one per launch.
        let uid = "crash-\(Int(record.start.timeIntervalSinceReferenceDate))"
        try store.record(record, to: p, uid: uid)
        try store.record(record, to: p, uid: uid)

        XCTAssertEqual(p.sessions.count, 1,
                       "a retry of the same crashed session is not a second one")
    }

    /// Dragging one block on top of another used to bill both.
    func testASessionCannotBeMovedOnTopOfAnother() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(9), end: date(12), activeSeconds: 10_800),
                         to: p, calendar: cal)
        try store.record(SessionRecord(start: date(13), end: date(17), activeSeconds: 14_400),
                         to: p, calendar: cal)
        let morning = try XCTUnwrap(p.sessions.min { $0.start < $1.start })

        XCTAssertThrowsError(try store.updateSession(morning, from: date(13), to: date(17),
                                                     calendar: cal)) { error in
            guard case SessionStore.SessionEditError.overlapsExisting = error else {
                return XCTFail("expected an overlap refusal, got \(error)")
            }
        }
        XCTAssertEqual(store.totalActiveSeconds(for: p), 25_200, accuracy: 1,
                       "and nothing moved")
    }

    /// A session dragged into tomorrow escapes its day's undo snapshot, so
    /// undoing the drag restores the original AND leaves the moved copy.
    func testASessionCannotBeDraggedOffItsOwnDay() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(14), end: date(18), activeSeconds: 14_400),
                         to: p, calendar: cal)
        let s = try XCTUnwrap(p.sessions.first)

        XCTAssertThrowsError(try store.updateSession(s, from: date(0, 0, day: 4),
                                                     to: date(4, 0, day: 4), calendar: cal)) { error in
            guard case SessionStore.SessionEditError.leavesItsDay = error else {
                return XCTFail("expected a day refusal, got \(error)")
            }
        }
        XCTAssertEqual(cal.startOfDay(for: s.start), cal.startOfDay(for: date(12)),
                       "and it is still on the day it was worked")
    }

    /// A refused edit leaves nothing half-applied in memory.
    ///
    /// Every reading surface — day totals, the strip, the unbilled figure,
    /// the invoice builder — reads the same objects the mutators write, so an
    /// edit that half-lands is an edit the screen shows and the disk does not
    /// have.
    ///
    /// Scope, stated plainly: this reaches the refusal through a GUARD, which
    /// throws before touching anything, so it does not exercise
    /// `SessionStore.commit`'s rollback. The rollback covers the other door —
    /// a `save()` that throws after the mutation — and there is no seam to
    /// force that on an in-memory container, so it is argued rather than
    /// tested. What is tested is the invariant both paths owe the caller.
    func testARefusedEditLeavesTheStoreAsItWas() throws {
        let p = try project()
        try store.record(SessionRecord(start: date(9), end: date(12), activeSeconds: 10_800),
                         to: p, calendar: cal)
        try store.record(SessionRecord(start: date(13), end: date(17), activeSeconds: 14_400),
                         to: p, calendar: cal)
        let before = store.dayTotals(for: p, calendar: cal).map(\.activeSeconds)
        let afternoon = try XCTUnwrap(p.sessions.max { $0.start < $1.start })

        try? store.updateSession(afternoon, from: date(10), to: date(11), calendar: cal)

        XCTAssertEqual(store.dayTotals(for: p, calendar: cal).map(\.activeSeconds), before)
        XCTAssertEqual(afternoon.start, date(13), "the object itself was not left rewritten")
        XCTAssertEqual(afternoon.end, date(17))
    }
}
