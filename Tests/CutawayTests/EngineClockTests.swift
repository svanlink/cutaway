import XCTest
@testable import Cutaway

/// The engine has an injectable clock so its behaviour is deterministic. One
/// moment ignored it: `closeSessionIfOpen` ended sessions on the wall clock —
/// and a session's end is what DaySplitter uses to decide which DAY the work
/// bills to. In production the two clocks agree, so this was latent; latent
/// in exactly the way that surfaces as a wrong day boundary no test can
/// reproduce, because the test could not reach it.
@MainActor
final class EngineClockTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    private var engine: DetectionEngine!
    private var probes: FakeProbes!
    private var clock: Date!
    private var store: UserDefaults!
    private var cal: Calendar!

    override func setUp() async throws {
        probes = FakeProbes()
        store = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        engine = DetectionEngine(probes: probes, defaults: store)
        cal = Calendar(identifier: .gregorian)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }
    private func tick(_ times: Int) { for _ in 0..<times { advance(1); engine.tick() } }

    func testAClosedSessionEndsOnTheEnginesClock() {
        engine.tick()
        tick(30)
        engine.togglePause()                       // closes the session

        let record = try! XCTUnwrap(engine.closedSessions.last)
        XCTAssertEqual(record.end, clock,
                       "the end must be the engine's now, not the machine's")
        // Sanity that the assertion above is not passing by coincidence: the
        // virtual clock sits months away from this machine's, in whichever
        // direction the test date happens to fall.
        XCTAssertGreaterThan(abs(record.end.timeIntervalSince(Date())), 86_400,
                             "the virtual clock must be nowhere near the wall clock")
    }

    /// The reason this matters: the end timestamp decides the day.
    func testASessionClosedAcrossVirtualMidnightBillsToTheRightDay() {
        // 23:59:40 on a virtual day.
        let midnight = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        clock = midnight.addingTimeInterval(86_400 - 20)
        engine.tick()
        tick(10)                                    // still yesterday
        advance(30)                                 // now past midnight
        engine.tick()                               // rollover closes the session

        let record = try! XCTUnwrap(engine.closedSessions.last)
        // `midnight` is the start of the day the session ran in; the clock was
        // wound to 20s before the NEXT midnight.
        XCTAssertTrue(cal.isDate(record.start, inSameDayAs: midnight),
                      "the session began on the earlier day")
        let parts = DaySplitter.split(record, calendar: cal)
        let total = parts.reduce(0) { $0 + $1.activeSeconds }
        XCTAssertEqual(total, record.activeSeconds, accuracy: 0.001,
                       "splitting must conserve every tracked second")
        XCTAssertEqual(record.end, clock, "closed on the virtual clock")
    }

    /// The crash snapshot's timestamp becomes a recovered session's END, so
    /// it has to come from the same clock as everything else.
    func testTheCrashSnapshotIsStampedOnTheEnginesClock() {
        engine.tick()
        tick(20)                                    // past the 15s checkpoint
        let stamp = store.double(forKey: "openSession.updatedAt")
        XCTAssertGreaterThan(stamp, 0, "a recording session must checkpoint")
        // Checkpoints land every 15s, so the newest stamp trails `now` by up
        // to that much — what matters is that it is on the virtual timeline.
        XCTAssertEqual(stamp, clock.timeIntervalSince1970, accuracy: 16,
                       "the snapshot must sit on the engine's clock")
        XCTAssertGreaterThan(abs(stamp - Date().timeIntervalSince1970), 86_400,
                             "and must not carry a wall-clock time into recovery")
    }

    func testCheckpointingDoesNotDependOnConstructionTime() {
        // A seed taken at construction would make the first checkpoint due
        // 15 wall-clock seconds after the engine existed, not 15 tracked ones.
        engine.tick()
        tick(1)
        XCTAssertGreaterThan(store.double(forKey: "openSession.start"), 0,
                             "the first checkpoint lands immediately, on the engine's clock")
    }
}
