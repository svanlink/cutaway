import XCTest
@testable import Cutaway

/// The app used to pause silently at the idle threshold — honest, but silent:
/// an editor reading a script or thinking through a cut lost the clock
/// without any chance to say "I'm here." The warning occupies the LAST
/// stretch of the existing tolerance, so an unanswered prompt pauses at
/// exactly the moment the app already paused. Billing is unchanged by
/// construction; these tests hold that construction in place.
@MainActor
final class IdleWarningTests: XCTestCase {

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
        let scratch = scratchDefaults()
        engine = DetectionEngine(probes: probes, defaults: scratch)
        engine.idleThreshold = 120
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { [weak self] in self!.clock }
    }

    private func tick(_ seconds: TimeInterval = 1) {
        clock = clock.addingTimeInterval(seconds)
        engine.tick()
    }

    // MARK: - The window

    func testNoWarningWhileInputIsFresh() {
        tick()
        XCTAssertEqual(engine.state, .recording)
        XCTAssertNil(engine.idleWarning, "a working user must never see the prompt")
    }

    func testTheWarningOpensThirtySecondsBeforeThePause() {
        tick()
        probes.idle = 89
        tick()
        XCTAssertNil(engine.idleWarning, "one second early is still too early")
        probes.idle = 91
        tick()
        let warning = engine.idleWarning
        XCTAssertNotNil(warning)
        XCTAssertEqual(warning!.secondsLeft, 29, accuracy: 0.001)
        XCTAssertEqual(engine.state, .recording, "warning is not a pause")
    }

    func testTheCountdownTracksTheIdleClock() {
        tick()
        probes.idle = 100
        tick()
        XCTAssertEqual(engine.idleWarning!.secondsLeft, 20, accuracy: 0.001)
        probes.idle = 115
        tick()
        XCTAssertEqual(engine.idleWarning!.secondsLeft, 5, accuracy: 0.001)
    }

    /// The invariant the whole design rests on: an unanswered warning pauses
    /// at the SAME threshold as before the feature existed.
    func testAnUnansweredWarningPausesExactlyAtTheThreshold() {
        tick()
        probes.idle = 119
        tick()
        XCTAssertEqual(engine.state, .recording)
        probes.idle = 120
        tick()
        XCTAssertEqual(engine.state, .paused(.inputIdle))
        XCTAssertNil(engine.idleWarning, "a paused clock has nothing to warn about")
    }

    func testAnyInputDismissesTheWarning() {
        tick()
        probes.idle = 100
        tick()
        XCTAssertNotNil(engine.idleWarning)
        probes.idle = 0                        // the user moved the mouse
        tick()
        XCTAssertNil(engine.idleWarning)
        XCTAssertEqual(engine.state, .recording)
    }

    // MARK: - The confirmation

    func testConfirmingKeepsRecordingAndClearsTheWarning() {
        tick()
        probes.idle = 110
        tick()
        XCTAssertNotNil(engine.idleWarning)

        engine.confirmPresence()               // probe still says idle 110
        XCTAssertNil(engine.idleWarning, "an attestation is input")
        XCTAssertEqual(engine.state, .recording)

        // And the attestation ages like real input: with no further activity
        // the warning comes back and the pause eventually lands.
        probes.idle = 500                      // probe way past threshold
        clock = clock.addingTimeInterval(100)  // but confirm was 100s ago
        engine.tick()
        XCTAssertNotNil(engine.idleWarning, "100s after the attestation, the window reopens")
        clock = clock.addingTimeInterval(25)
        engine.tick()
        XCTAssertEqual(engine.state, .paused(.inputIdle),
                       "confirming buys one tolerance, not immunity")
    }

    func testConfirmingDoesNotInjectPhantomTime() {
        tick()
        probes.idle = 110
        tick()
        let before = engine.accumulator.activeSeconds
        engine.confirmPresence()
        XCTAssertEqual(engine.accumulator.activeSeconds, before,
                       "only the 1 Hz timer adds seconds — same rule as togglePause")
    }

    // MARK: - Suppression

    func testNoWarningDuringAProvenRender() {
        // The render exemption already carries idle stretches with CPU
        // evidence; a nag during an export teaches the user to ignore it.
        final class BusyProbes: SystemProbing, @unchecked Sendable {
            var frontmost: String? = DetectionInput.resolveBundleIDs[0]
            var idle: TimeInterval = 0
            var cpuNanos: UInt64 = 0
            func frontmostBundleID() -> String? { frontmost }
            func secondsSinceLastInput() -> TimeInterval { idle }
            func workAppCPUNanos(matching prefixes: [String]) -> UInt64 { cpuNanos }
        }
        let busy = BusyProbes()
        let scratch = scratchDefaults()
        let e = DetectionEngine(probes: busy, defaults: scratch)
        e.idleThreshold = 120
        e.renderExemption = true
        var c = Date(timeIntervalSince1970: 1_800_000_000)
        e.now = { c }
        e.tick()
        busy.idle = 130                        // past threshold, exemption active
        for _ in 0..<3 {
            busy.cpuNanos += 4_000_000_000     // 4 cores' worth per second
            c = c.addingTimeInterval(1)
            e.tick()
        }
        XCTAssertEqual(e.state, .recording, "the render exemption is carrying this")
        XCTAssertNil(e.idleWarning, "no nagging while the work is provably happening")
    }

    func testNoWarningWhilePaused() {
        tick()
        engine.togglePause()
        probes.idle = 100
        tick()
        XCTAssertNil(engine.idleWarning, "a manually paused clock has nothing to warn about")
    }

    // MARK: - Billing invariance

    func testTheWarningWindowBillsExactlyAsItAlwaysDid() {
        // The tail of the idle tolerance was always billed (the user might be
        // thinking); the warning must not change that in either direction.
        tick()
        let before = engine.accumulator.activeSeconds
        probes.idle = 95
        for _ in 0..<10 { tick() }             // ten seconds inside the window
        XCTAssertEqual(engine.accumulator.activeSeconds - before, 10, accuracy: 0.5,
                       "the warning is a warning, not a billing state")
    }

    // MARK: - Copy

    func testTheCountdownTextNeverGoesNegative() {
        XCTAssertEqual(IdleWarningView.countdownText(12), "Pauses in 12 s")
        XCTAssertEqual(IdleWarningView.countdownText(0.4), "Pauses in 0 s")
        XCTAssertEqual(IdleWarningView.countdownText(-3), "Pauses in 0 s")
    }
}
