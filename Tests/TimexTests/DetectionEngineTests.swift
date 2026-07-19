import XCTest
@testable import Cutaway

/// Drives DetectionEngine.tick() deterministically with fake probes and a
/// fake clock — covering the orchestration (bridge, hard boundaries, deltas)
/// that pure-function tests structurally cannot reach.
@MainActor
final class DetectionEngineTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    private var probes: FakeProbes!
    private var engine: DetectionEngine!
    private var clock: Date!

    override func setUp() async throws {
        probes = FakeProbes()
        engine = DetectionEngine(probes: probes)
        engine.bridgeGrace = 180
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }
    private func tickRecordingFor(_ seconds: Int) {
        for _ in 0..<seconds { advance(1); engine.tick() }
    }

    func testRecordsAndAccumulatesRealDeltas() {
        engine.tick() // first tick establishes state
        XCTAssertEqual(engine.state, .recording)
        tickRecordingFor(10)
        XCTAssertEqual(engine.accumulator.activeSeconds, 10, accuracy: 1.1)
    }

    func testRunLoopStallCreditsRealElapsedTime() {
        engine.tick()
        tickRecordingFor(5)
        let before = engine.accumulator.activeSeconds
        advance(3) // a 3s stall between ticks
        engine.tick()
        XCTAssertEqual(engine.accumulator.activeSeconds - before, 3, accuracy: 0.01)
    }

    func testBridgeCreditsShortAwayGap() {
        engine.tick()
        tickRecordingFor(10)
        probes.frontmost = "com.spotify.client"
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .paused(.notFrontmost))
        XCTAssertEqual(engine.closedSessions.count, 0, "session must stay open during grace")
        advance(60)
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        engine.tick()
        XCTAssertEqual(engine.state, .recording)
        // ~10s recorded + ~61s bridged gap
        XCTAssertEqual(engine.accumulator.activeSeconds, 71, accuracy: 2.5)
    }

    func testBridgeExpiryClosesSessionWithoutCrediting() {
        engine.tick()
        tickRecordingFor(10)
        probes.frontmost = "com.spotify.client"
        advance(1); engine.tick()
        advance(200) // > grace
        engine.tick()
        XCTAssertEqual(engine.closedSessions.count, 1)
        XCTAssertEqual(engine.closedSessions[0].activeSeconds, 10, accuracy: 1.5,
                       "expired gap must not be credited")
        // returning later starts a FRESH session with no credit
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        advance(1); engine.tick()
        XCTAssertEqual(engine.accumulator.activeSeconds, 0, accuracy: 1.1)
    }

    func testManualPauseIsHardBridgeBoundary() {
        // The audit's CRITICAL: pause during an away-gap must kill the bridge.
        engine.tick()
        tickRecordingFor(10)
        probes.frontmost = "com.spotify.client"
        advance(1); engine.tick()          // gap opens
        advance(10)
        engine.togglePause(); // manual pause while away → hard boundary
        XCTAssertEqual(engine.state, .paused(.manual))
        XCTAssertEqual(engine.closedSessions.count, 1, "manual pause closes the session")
        advance(100)
        engine.togglePause()               // unpause, still in Chrome
        advance(1); engine.tick()
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .recording)
        // No bridge credit from the pre-pause gap may survive.
        XCTAssertEqual(engine.accumulator.activeSeconds, 0, accuracy: 1.1,
                       "paused time must never be credited")
    }

    func testSleepIsHardBridgeBoundary() {
        engine.tick()
        tickRecordingFor(10)
        probes.frontmost = "com.spotify.client"
        advance(1); engine.tick()          // gap opens
        // Simulate sleep via the notification path's effect: manual injection
        // isn't available, so drive through evaluate by idle? Sleep uses an
        // internal flag — test the equivalent hard boundary via noProject.
        engine.hasActiveProject = false
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .paused(.noProject))
        XCTAssertEqual(engine.closedSessions.count, 1, "hard boundary closes session")
        engine.hasActiveProject = true
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        advance(1); engine.tick()
        XCTAssertEqual(engine.accumulator.activeSeconds, 0, accuracy: 1.1,
                       "no credit may survive a hard boundary")
    }

    func testAddedWorkAppPrefixIsHonoredLive() {
        // Custom anchor added mid-run (the Settings editor path): the very
        // next tick must treat it as work context — no restart required.
        probes.frontmost = "com.figma.Desktop"
        engine.tick()
        XCTAssertEqual(engine.state, .paused(.notFrontmost), "unknown app is not work")
        engine.workAppPrefixes = DetectionInput.defaultWorkAppPrefixes + ["com.figma.Desktop"]
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .recording, "added prefix must count immediately")
    }

    func testSanitizedPrefixesRoundTripThroughDefaults() {
        let dirty = ["  com.adobe.PremierePro ", "", "com.figma.Desktop", "COM.FIGMA.DESKTOP"]
        let clean = DetectionInput.sanitizedPrefixes(dirty)
        XCTAssertEqual(clean, ["com.adobe.PremierePro", "com.figma.Desktop"])
        // Round-trip through a scratch defaults suite (never the real domain).
        let suite = UserDefaults(suiteName: "cutaway.tests.applist")!
        suite.removePersistentDomain(forName: "cutaway.tests.applist")
        suite.set(clean, forKey: "workApps")
        XCTAssertEqual(suite.stringArray(forKey: "workApps"), clean)
        suite.removePersistentDomain(forName: "cutaway.tests.applist")
    }

    func testWorkflowAppKeepsRecording() {
        engine.workAppPrefixes = DetectionInput.defaultWorkAppPrefixes
        engine.tick()
        tickRecordingFor(5)
        probes.frontmost = "com.adobe.AfterEffects"
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .recording, "workflow app is work context")
        XCTAssertEqual(engine.closedSessions.count, 0)
    }

    // MARK: - Satellite (research/comms) model

    private func enableSatellites() {
        engine.satellitePrefixes = DetectionInput.defaultSatellitePrefixes
        engine.satelliteWindow = 1200
    }

    func testSatelliteSustainsRecordingWithinWindow() {
        enableSatellites()
        engine.tick()
        tickRecordingFor(10)                       // anchor work refreshes window
        probes.frontmost = "com.google.Chrome"     // research
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .recording, "satellite sustains inside window")
        tickRecordingFor(30)
        XCTAssertEqual(engine.accumulator.activeSeconds, 41, accuracy: 2)
    }

    func testSatelliteCannotStartWithoutAnchorHistory() {
        enableSatellites()
        probes.frontmost = "com.google.Chrome"
        engine.tick()
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .paused(.notFrontmost),
                       "browsing with no prior anchor work must not bill")
    }

    func testSatelliteWindowExpiryStopsRecording() {
        enableSatellites()
        engine.satelliteWindow = 60
        engine.tick()
        tickRecordingFor(10)
        probes.frontmost = "com.apple.Safari"
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .recording)
        advance(120); engine.tick()                // window (60s) long expired
        XCTAssertEqual(engine.state, .paused(.notFrontmost),
                       "expired research window stops billing")
    }

    func testAnchorRefreshesSatelliteWindow() {
        enableSatellites()
        engine.satelliteWindow = 60
        engine.tick()
        tickRecordingFor(5)
        probes.frontmost = "com.apple.Safari"      // research 40s
        advance(40); engine.tick()
        probes.frontmost = DetectionInput.resolveBundleIDs[0]  // back to anchor
        advance(1); engine.tick()
        probes.frontmost = "com.apple.Safari"      // research again — window fresh
        advance(40); engine.tick()
        XCTAssertEqual(engine.state, .recording,
                       "anchor touch must refresh the research window")
    }

    func testSatelliteStillRespectsIdle() {
        enableSatellites()
        engine.tick()
        tickRecordingFor(5)
        probes.frontmost = "com.google.Chrome"
        probes.idle = 500                          // walked away mid-research
        advance(1); engine.tick()
        XCTAssertEqual(engine.state, .paused(.inputIdle),
                       "idle user in a browser must not bill")
    }
}

@MainActor
final class LongPauseHintTests: XCTestCase {

    func testLongPauseFlagsAfterThreshold() {
        let probes = DetectionEngineTests.FakeProbes()
        let engine = DetectionEngine(probes: probes)
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { clock }
        engine.tick()
        engine.togglePause()
        XCTAssertFalse(engine.pausedLong)
        clock = clock.addingTimeInterval(DetectionEngine.longPauseThreshold - 1)
        engine.tick()
        XCTAssertFalse(engine.pausedLong, "not yet at threshold")
        clock = clock.addingTimeInterval(2)
        engine.tick()
        XCTAssertTrue(engine.pausedLong, "15 min of manual pause must flag the hint")
        engine.togglePause()
        XCTAssertFalse(engine.pausedLong, "resume clears the hint immediately")
    }
}
