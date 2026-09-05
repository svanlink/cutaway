import XCTest
@testable import Cutaway

/// The idle-during-render exemption is the ONE rule in this app that resolves
/// ambiguity toward billing more, so it is fenced on every side: off by
/// default, evidence-required, capped, and outranked by every hard boundary.
@MainActor
final class RenderExemptionTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        var cpuNanos: UInt64 = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
        func workAppCPUNanos(matching prefixes: [String]) -> UInt64 { cpuNanos }
    }

    private var probes: FakeProbes!
    private var engine: DetectionEngine!
    private var clock: Date!

    override func setUp() async throws {
        probes = FakeProbes()
        let scratch = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        engine = DetectionEngine(probes: probes, defaults: scratch)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
        engine.idleThreshold = 120
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }

    /// One second of wall time at `percent` of a core.
    private func burn(_ percent: Double, seconds: TimeInterval = 1) {
        probes.cpuNanos += UInt64(percent / 100 * seconds * 1_000_000_000)
        advance(seconds)
        engine.tick()
    }

    func testOffByDefaultIdleStillPauses() {
        engine.tick()
        XCTAssertEqual(engine.state, .recording)
        probes.idle = 300
        burn(400)  // a render at 4 cores — but the toggle is off
        XCTAssertEqual(engine.state, .paused(.inputIdle),
                       "the exemption must do nothing until the user opts in")
    }

    func testBusyRenderKeepsRecordingThroughIdle() {
        engine.renderExemption = true
        engine.tick()
        probes.idle = 300
        burn(400); burn(400)
        XCTAssertEqual(engine.state, .recording, "a provably busy render keeps billing")
        // Tick by tick, as the real 1 Hz timer does — a single 10s jump would
        // hit the engine's deliberate 5s stall cap instead.
        let before = engine.accumulator.activeSeconds
        for _ in 0..<10 { burn(400) }
        XCTAssertEqual(engine.accumulator.activeSeconds - before, 10, accuracy: 0.01,
                       "exempted render time accrues like any other recording")
    }

    func testIdleWithoutLoadStillPauses() {
        engine.renderExemption = true
        engine.tick()
        probes.idle = 300
        burn(5); burn(5)  // Resolve open, idling — not a render
        XCTAssertEqual(engine.state, .paused(.inputIdle),
                       "an open app is not evidence of work; cpu load is")
    }

    func testExemptionExpiresAtTheCap() {
        engine.renderExemption = true
        engine.tick()
        probes.idle = 300
        burn(400)
        burn(400, seconds: DetectionEngine.renderExemptionCap - 1)
        XCTAssertEqual(engine.state, .recording, "still inside the cap")
        burn(400, seconds: 60)
        XCTAssertEqual(engine.state, .paused(.inputIdle),
                       "an unattended overnight render is not a working day")
    }

    func testManualPauseOutranksTheExemption() {
        engine.renderExemption = true
        engine.tick()
        probes.idle = 300
        burn(400); burn(400)
        XCTAssertEqual(engine.state, .recording)
        engine.togglePause()
        XCTAssertEqual(engine.state, .paused(.manual),
                       "manual pause is sacred — no render outranks it")
    }

    func testLeavingTheWorkContextOutranksTheExemption() {
        engine.renderExemption = true
        engine.tick()
        probes.idle = 300
        burn(400); burn(400)
        XCTAssertEqual(engine.state, .recording)
        probes.frontmost = "com.spotify.client"
        burn(400)
        XCTAssertEqual(engine.state, .paused(.notFrontmost),
                       "a render does not bill time spent somewhere else")
    }

    func testReturningInputRearmsTheExemption() {
        engine.renderExemption = true
        engine.tick()
        probes.idle = 300
        burn(400)
        burn(400, seconds: DetectionEngine.renderExemptionCap + 60)
        XCTAssertEqual(engine.state, .paused(.inputIdle))
        probes.idle = 0
        burn(400)
        XCTAssertEqual(engine.state, .recording, "the user came back")
        probes.idle = 300
        burn(400); burn(400)
        XCTAssertEqual(engine.state, .recording, "a fresh idle stretch gets a fresh cap")
    }
}
