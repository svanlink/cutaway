import XCTest
@testable import Cutaway

/// Closing Resolve must stop the clock — and this time the rule has to be
/// wired, not merely written.
///
/// Reported live on 2026-09-09: Resolve closed several minutes earlier, no
/// Adobe app running, frontmost was a satellite (Claude), and the engine was
/// still accumulating — checkpoints 47, 62, 77 seconds. The cause was not
/// the rule. `isWorkContext` has required `anchorAppRunning` for satellites
/// since the fix that was supposed to close this. The engine simply never
/// assigned it: `DetectionInput.anchorAppRunning` defaults to true, the
/// probe was implemented and declared, and `tick()` did not set it. The
/// requirement had been inert since the day it shipped.
///
/// Third time this exact shape has appeared — freshProjectName had zero
/// callers, DetectionFollower is instantiated and bypassed — so this test
/// checks the WIRING, not the struct.
@MainActor
final class AnchorRunningWiringTests: XCTestCase {

    final class Probes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = "com.anthropic.claudefordesktop"
        var idle: TimeInterval = 0
        var anchorRunning = false
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
        func anchorAppRunning(matching prefixes: [String]) -> Bool { anchorRunning }
    }

    private var probes: Probes!
    private var engine: DetectionEngine!
    private var clock: Date!

    override func setUp() async throws {
        probes = Probes()
        engine = DetectionEngine(probes: probes, defaults: scratchDefaults())
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [unowned self] in self.clock }
        engine.hasActiveProject = true
        engine.workAppPrefixes = DetectionInput.resolveBundleIDs
        engine.satellitePrefixes = ["com.anthropic"]
        engine.anchorNamedAProject = true
    }

    /// Anchor frontmost opens the research window; the satellite then
    /// sustains recording — but only while an anchor is still running.
    private func openTheResearchWindow() {
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        probes.anchorRunning = true
        for _ in 0..<3 { clock += 1; engine.tick() }
        XCTAssertEqual(engine.state, .recording, "Resolve in front records")
    }

    func testASatelliteStopsCountingOnceTheAnchorIsGone() {
        openTheResearchWindow()
        probes.frontmost = "com.anthropic.claudefordesktop"
        clock += 1; engine.tick()
        XCTAssertEqual(engine.state, .recording, "still inside the research window, Resolve up")

        // Resolve quits. Nothing else about the world changes.
        probes.anchorRunning = false
        clock += 1; engine.tick()
        XCTAssertEqual(engine.state, .paused(.notFrontmost),
                       "no anchor is running: research is not billable on its own")
    }

    func testTheSatelliteKeepsCountingWhileAnAnchorIsStillOpen() {
        openTheResearchWindow()
        probes.frontmost = "com.anthropic.claudefordesktop"
        for _ in 0..<5 { clock += 1; engine.tick() }
        XCTAssertEqual(engine.state, .recording,
                       "Resolve is still open — reading docs for the job is the job")
    }
}
