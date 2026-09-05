import XCTest
@testable import Cutaway

/// Manual pause is the boundary this app calls sacred: time behind it is
/// never billed, no matter what. It held within a run and lifted silently
/// across one — quit while paused and the app came back recording, accruing
/// time the user believed was stopped, with nothing on screen to say so.
@MainActor
final class PausePersistenceTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    /// One simulated install: a store that outlives the engines built on it,
    /// which is exactly what UserDefaults is to a real app.
    private var store: UserDefaults!

    override func setUp() async throws {
        store = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
    }

    /// A fresh engine over the same store — what a relaunch actually is.
    private func relaunch(clock: Date) -> (DetectionEngine, FakeProbes) {
        let probes = FakeProbes()
        let engine = DetectionEngine(probes: probes, defaults: store)
        engine.now = { clock }
        return (engine, probes)
    }

    func testAPauseSurvivesRelaunch() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (first, _) = relaunch(clock: clock)
        first.tick()
        XCTAssertEqual(first.state, .recording)
        first.togglePause()
        XCTAssertEqual(first.state, .paused(.manual))

        // ...quit, and come back an hour later...
        clock = clock.addingTimeInterval(3600)
        let (second, _) = relaunch(clock: clock)
        second.tick()
        XCTAssertTrue(second.manuallyPaused, "the user never resumed")
        XCTAssertEqual(second.state, .paused(.manual))
    }

    func testNoTimeAccruesAcrossTheRelaunch() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (first, _) = relaunch(clock: clock)
        first.tick()
        first.togglePause()

        var later = clock.addingTimeInterval(600)
        let probes = FakeProbes()
        let second = DetectionEngine(probes: probes, defaults: store)
        second.now = { later }
        for _ in 0..<60 { later = later.addingTimeInterval(1); second.tick() }
        XCTAssertEqual(second.accumulator.activeSeconds, 0,
                       "a restored pause must not bill a single second")
        XCTAssertNil(second.accumulator.sessionStart)
    }

    func testResumingClearsThePersistedPause() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (first, _) = relaunch(clock: clock)
        first.tick()
        first.togglePause()
        first.togglePause()          // user resumes

        let (second, _) = relaunch(clock: clock)
        second.tick()
        XCTAssertFalse(second.manuallyPaused)
        XCTAssertEqual(second.state, .recording, "a resumed timer must come back running")
        XCTAssertNil(second.manualPauseStart)
    }

    func testANeverPausedInstallIsUnaffected() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (engine, _) = relaunch(clock: clock)
        engine.tick()
        XCTAssertFalse(engine.manuallyPaused)
        XCTAssertEqual(engine.state, .recording)
    }

    /// A pause restored at launch reports its real age, so the
    /// forgotten-pause hint fires at once instead of restarting its clock.
    func testARestoredPauseReportsItsRealAge() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (first, _) = relaunch(clock: clock)
        first.tick()
        first.togglePause()

        let nextDay = clock.addingTimeInterval(86_400)
        let (second, _) = relaunch(clock: nextDay)
        second.tick()
        XCTAssertEqual(second.manualPauseStart, clock, "the pause began yesterday, not at launch")
        XCTAssertTrue(second.pausedLong,
                      "a day-old pause is exactly what the forgotten-pause hint is for")
    }

    func testAStartWithoutAPauseIsNotRestored() {
        store.set(Date().timeIntervalSince1970, forKey: PauseState.startKey)
        store.set(false, forKey: PauseState.pausedKey)
        XCTAssertNil(PauseState.restoredStart(from: store),
                     "a half-restored pause is worse than none")
    }
}
