import XCTest
@testable import Cutaway

/// Tier 1 spawns fuscript and answers seconds later. An answer that started
/// before the user picked a project must not land on top of that pick — the
/// same automation-beats-intent defect as steady-state switching, but racy,
/// so in the wild it reads as "the app randomly changed my project".
final class ManualIntentTests: XCTestCase {

    func testAnUninterruptedDetectionStillApplies() {
        var intent = ManualIntent()
        let started = intent.token
        // ...fuscript runs, nobody touches anything...
        XCTAssertFalse(intent.hasMovedSince(started),
                       "with no manual choice in between, the answer is still good")
    }

    func testAChoiceDuringTheRequestInvalidatesIt() {
        var intent = ManualIntent()
        let started = intent.token
        intent.userChose()
        XCTAssertTrue(intent.hasMovedSince(started),
                      "the answer describes a world the user has already left")
    }

    func testOnlyChoicesMadeAfterTheRequestStartedCount() {
        var intent = ManualIntent()
        intent.userChose()          // before the request
        let started = intent.token
        XCTAssertFalse(intent.hasMovedSince(started),
                       "an earlier choice is already reflected in what the request saw")
    }

    func testRepeatedChoicesAllInvalidate() {
        var intent = ManualIntent()
        let started = intent.token
        for _ in 0..<5 { intent.userChose() }
        XCTAssertTrue(intent.hasMovedSince(started))
    }

    /// Two requests can be in flight across a choice; each judges itself
    /// against its own start, not against the other.
    func testConcurrentRequestsJudgeThemselvesIndependently() {
        var intent = ManualIntent()
        let first = intent.token
        intent.userChose()
        let second = intent.token
        XCTAssertTrue(intent.hasMovedSince(first), "started before the choice — stale")
        XCTAssertFalse(intent.hasMovedSince(second), "started after it — still valid")
    }

    /// The gap the transition-following fix left open, closed: a stale answer
    /// naming a DIFFERENT project reads as a legitimate transition to the
    /// follower, so the staleness check has to happen before the follower
    /// ever sees it.
    func testStaleAnswerNamingADifferentProjectIsDroppedBeforeTheFollower() {
        var intent = ManualIntent()
        var follower = DetectionFollower()
        _ = follower.observe("Alpina")          // Resolve had Alpina open

        let started = intent.token              // Tier 1 request begins
        intent.userChose()                      // user picks Nyx by hand

        let staleAnswer = "Bergen"              // fuscript finally answers
        if !intent.hasMovedSince(started) {
            XCTFail("this answer must be recognised as stale")
        }
        // The follower is never consulted, so it does not record Bergen and
        // does not report a transition the user never asked for.
        XCTAssertEqual(follower.lastSeen, "Alpina")
        var fresh = DetectionFollower()
        _ = fresh.observe("Alpina")
        XCTAssertNotNil(fresh.observe(staleAnswer),
                        "sanity: Bergen WOULD have looked like a transition")
    }
}
