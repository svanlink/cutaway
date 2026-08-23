import XCTest
@testable import Cutaway

/// The reclaim prompt is the one feature that can move money AFTER the fact,
/// so every default points the honest way: default No, timing out to No,
/// sacred pauses never offered, nothing billed without an explicit click.
/// These tests are the fence around that.
@MainActor
final class ReclaimOfferTests: XCTestCase {

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
        let scratch = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        engine = DetectionEngine(probes: probes, defaults: scratch)
        engine.idleThreshold = 120
        engine.bridgeGrace = 180
        // Midday, so no test gap straddles midnight by accident.
        clock = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0,
            of: Date(timeIntervalSince1970: 1_800_000_000))!
        engine.now = { [weak self] in self!.clock }
    }

    private func tick(_ seconds: TimeInterval = 1) {
        clock = clock.addingTimeInterval(seconds)
        engine.tick()
    }

    private func startRecording() {
        engine.tick()
        XCTAssertEqual(engine.state, .recording)
    }

    // MARK: - When the offer appears

    /// The motivating case: a client call with Resolve still frontmost.
    /// Idle pause at the threshold, back ten minutes later.
    func testALongIdleGapIsOfferedBack() {
        startRecording()
        probes.idle = 120
        tick()
        XCTAssertEqual(engine.state, .paused(.inputIdle))
        let pausedAt = clock!

        tick(600)                              // ten minutes on the phone
        probes.idle = 0
        tick()
        XCTAssertEqual(engine.state, .recording)
        let offer = engine.reclaimOffer
        XCTAssertNotNil(offer, "an automatic pause the user never asked for is reclaim-eligible")
        XCTAssertEqual(offer!.seconds, clock.timeIntervalSince(pausedAt), accuracy: 1.5,
                       "the gap runs from where billing stopped to where it resumed")
    }

    /// Reference footage on another machine: bridge expires, back later.
    /// The gap runs from when the user LEFT, not from when the bridge gave up.
    func testAnExpiredBridgeGapIsOfferedFromTheMomentOfLeaving() {
        startRecording()
        tick(10)
        probes.frontmost = "com.spotify.client"
        tick()
        let leftAt = clock!
        XCTAssertEqual(engine.state, .paused(.notFrontmost))

        tick(200)                              // grace expires along the way
        XCTAssertEqual(engine.closedSessions.count, 1, "bridge gave up")
        tick(400)                              // still away
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        tick()
        XCTAssertEqual(engine.state, .recording)
        let offer = engine.reclaimOffer
        XCTAssertNotNil(offer)
        XCTAssertEqual(offer!.seconds, clock.timeIntervalSince(leftAt), accuracy: 2.5,
                       "the whole away span went unbilled, so the whole span is the offer")
    }

    // MARK: - When it must NOT appear

    func testAShortIdleGapIsNotWorthAPrompt() {
        startRecording()
        probes.idle = 120
        tick()
        tick(60)                               // one minute — a stretch, a coffee
        probes.idle = 0
        tick()
        XCTAssertEqual(engine.state, .recording)
        XCTAssertNil(engine.reclaimOffer,
                     "the offer starts where the bridge ends; below that it is noise")
    }

    func testABridgedGapIsAlreadyHandled() {
        startRecording()
        tick(10)
        probes.frontmost = "com.spotify.client"
        tick()
        tick(60)
        probes.frontmost = DetectionInput.resolveBundleIDs[0]
        tick()
        XCTAssertEqual(engine.state, .recording)
        XCTAssertNil(engine.reclaimOffer, "the bridge credited this one automatically")
    }

    func testAManualPauseIsNeverOfferedBack() {
        startRecording()
        engine.togglePause()
        tick(600)
        engine.togglePause()                   // user resumes by hand
        tick()
        XCTAssertEqual(engine.state, .recording)
        XCTAssertNil(engine.reclaimOffer, "the user said stop; that boundary is sacred")
    }

    func testAGapBeyondTheCapIsNotOffered() {
        startRecording()
        probes.idle = 120
        tick()
        tick(3 * 3600)                         // three hours is a break, not a detour
        probes.idle = 0
        tick()
        XCTAssertNil(engine.reclaimOffer,
                     "a one-click 'add 3 hours' is an invoice mistake waiting to happen")
    }

    // MARK: - Answering

    func testAcceptingCreditsExactlyTheGapAndOnlyOnce() {
        startRecording()
        probes.idle = 120
        tick()
        tick(600)
        probes.idle = 0
        tick()
        let offered = engine.reclaimOffer!.seconds
        let before = engine.accumulator.activeSeconds

        engine.acceptReclaim()
        XCTAssertEqual(engine.accumulator.activeSeconds - before, offered, accuracy: 0.001,
                       "yes bills exactly the gap — no rounding in the house's favour")
        XCTAssertNil(engine.reclaimOffer)

        engine.acceptReclaim()                 // a double-click must not double-bill
        XCTAssertEqual(engine.accumulator.activeSeconds - before, offered, accuracy: 0.001)
    }

    func testDecliningCreditsNothing() {
        startRecording()
        probes.idle = 120
        tick()
        tick(600)
        probes.idle = 0
        tick()
        let before = engine.accumulator.activeSeconds
        engine.declineReclaim()
        XCTAssertNil(engine.reclaimOffer)
        tick(5)
        XCTAssertEqual(engine.accumulator.activeSeconds - before, 5, accuracy: 0.5,
                       "only the seconds actually worked since resuming")
    }

    /// Ignoring the card IS answering No.
    func testAnIgnoredOfferLapsesWithoutBillingAnything() {
        startRecording()
        probes.idle = 120
        tick()
        tick(600)
        probes.idle = 0
        tick()
        XCTAssertNotNil(engine.reclaimOffer)
        let before = engine.accumulator.activeSeconds

        for _ in 0..<(Int(ReclaimOffer.duration) + 2) { tick() }
        XCTAssertNil(engine.reclaimOffer, "silence means no")
        // Only the worked seconds since resume were billed — the gap was not.
        XCTAssertEqual(engine.accumulator.activeSeconds - before,
                       ReclaimOffer.duration + 2, accuracy: 2,
                       "the lapsed offer must leave billing exactly as if it never appeared")
    }

    func testPausingAgainKillsTheOffer() {
        startRecording()
        probes.idle = 120
        tick()
        tick(600)
        probes.idle = 0
        tick()
        XCTAssertNotNil(engine.reclaimOffer)
        engine.togglePause()
        XCTAssertNil(engine.reclaimOffer,
                     "the offer credits a running session; without one it has no target")
    }

    func testSleepDuringTheGapCancelsIt() {
        startRecording()
        probes.idle = 120
        tick()                                 // idle pause, gap opens
        engine.togglePause()                   // stand-in for a hard boundary arriving
        engine.togglePause()
        probes.idle = 0
        tick()
        XCTAssertEqual(engine.state, .recording)
        XCTAssertNil(engine.reclaimOffer, "a hard boundary inside the gap voids it")
    }

    // MARK: - Copy

    func testTheGapTextFloorsToTheMinute() {
        XCTAssertEqual(ReclaimView.gapText(14 * 60 + 42), "14 min")
        XCTAssertEqual(ReclaimView.gapText(80 * 60), "1 h 20 min")
        XCTAssertEqual(ReclaimView.gapText(200), "3 min")
    }
}
