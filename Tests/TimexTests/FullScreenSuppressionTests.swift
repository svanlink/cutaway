import XCTest
@testable import Cutaway

/// A full-screen anchor is the one place the "still working?" card is
/// harmful: playback in front of a client generates no input, and a floating
/// card over the picture is worse than the silent pause the app always had.
/// Suppressed, the pause lands at the threshold exactly as it did before the
/// panel existed.
@MainActor
final class FullScreenSuppressionTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        var fullScreen = false
        var fullScreenQueries = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
        func frontmostWindowIsFullScreen() -> Bool {
            fullScreenQueries += 1
            return fullScreen
        }
    }

    private var probes: FakeProbes!
    private var engine: DetectionEngine!
    private var clock: Date!

    override func setUp() async throws {
        probes = FakeProbes()
        let scratch = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        engine = DetectionEngine(probes: probes, defaults: scratch)
        engine.idleThreshold = 120
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
    }

    private func tick(_ seconds: TimeInterval = 1) {
        clock = clock.addingTimeInterval(seconds)
        engine.tick()
    }

    /// The client viewing session: Resolve full-screen, playback rolling,
    /// nobody touching anything.
    func testNoCardOverFullScreenResolve() {
        tick()
        probes.fullScreen = true
        probes.idle = 100                       // inside the warning window
        tick()
        XCTAssertNil(engine.idleWarning, "no floating card over the client's picture")
        XCTAssertEqual(engine.state, .recording, "suppression hides the card, not the clock")
    }

    /// And the pause still lands, silently, exactly where it always did.
    func testTheSuppressedPauseStillLandsAtTheThreshold() {
        tick()
        probes.fullScreen = true
        probes.idle = 120
        tick()
        XCTAssertEqual(engine.state, .paused(.inputIdle),
                       "silent, as it was before the panel existed")
    }

    func testTheCardStillShowsInWindowedResolve() {
        tick()
        probes.fullScreen = false
        probes.idle = 100
        tick()
        XCTAssertNotNil(engine.idleWarning, "windowed editing keeps the warning")
    }

    /// A full-screen BROWSER does not suppress: an evening of full-screen
    /// video is precisely what the idle pause exists for.
    func testAFullScreenSatelliteDoesNotSuppress() {
        tick()                                  // anchor activity opens the window
        probes.frontmost = "com.google.Chrome"
        probes.fullScreen = true
        probes.idle = 100
        tick()
        XCTAssertEqual(engine.state, .recording, "satellite sustains inside the research window")
        XCTAssertNotNil(engine.idleWarning,
                        "full-screen video in a browser earns the warning, not a pass")
    }

    /// Leaving full-screen mid-window brings the card back with the time
    /// that is actually left.
    func testExitingFullScreenRevealsTheRemainingCountdown() {
        tick()
        probes.fullScreen = true
        probes.idle = 100
        tick()
        XCTAssertNil(engine.idleWarning)
        probes.fullScreen = false
        probes.idle = 110
        tick()
        let warning = engine.idleWarning
        XCTAssertNotNil(warning)
        XCTAssertEqual(warning!.secondsLeft, 10, accuracy: 0.001)
    }

    /// The window-list walk is not a per-second cost: the probe is consulted
    /// only when a warning is otherwise about to show.
    func testTheProbeIsOnlyAskedInsideTheWarningWindow() {
        for _ in 0..<20 { tick() }              // fresh input throughout
        XCTAssertEqual(probes.fullScreenQueries, 0,
                       "a working user never pays for the window list")
        probes.idle = 100
        tick()
        XCTAssertEqual(probes.fullScreenQueries, 1, "asked exactly when it matters")
    }
}
