import XCTest
@testable import Cutaway

/// "Why isn't this counting?" is the first question a new user has, and the
/// answer used to live only in the README. These lock the branches — in
/// particular that a quiet afternoon is not mistaken for an empty app.
@MainActor
final class ZeroStateTests: XCTestCase {

    func testNoProjectOutranksEverythingElse() {
        XCTAssertEqual(
            ZeroStatePolicy.zeroState(hasProject: false, trackedSeconds: 0,
                               isRecording: false, resolveRunning: true),
            .noProject,
            "with nothing to attribute time to, Resolve being open is irrelevant")
    }

    func testFreshProjectExplainsWhatStartsTheClock() {
        XCTAssertEqual(
            ZeroStatePolicy.zeroState(hasProject: true, trackedSeconds: 0,
                               isRecording: false, resolveRunning: false),
            .nothingTrackedYet(resolveRunning: false))
        XCTAssertEqual(
            ZeroStatePolicy.zeroState(hasProject: true, trackedSeconds: 0,
                               isRecording: false, resolveRunning: true),
            .nothingTrackedYet(resolveRunning: true))
    }

    func testRecordedHistoryIsNotAZeroState() {
        XCTAssertNil(
            ZeroStatePolicy.zeroState(hasProject: true, trackedSeconds: 3600,
                               isRecording: false, resolveRunning: false),
            "a quiet afternoon on a project with history is not an empty app")
    }

    func testRecordingIsNeverAZeroState() {
        XCTAssertNil(
            ZeroStatePolicy.zeroState(hasProject: true, trackedSeconds: 0,
                               isRecording: true, resolveRunning: true),
            "the very first seconds are already being tracked — say nothing")
    }

    func testHintNeverPromisesDetectionThatCannotHappen() {
        let closed = ZeroStatePolicy.zeroStateHint(.nothingTrackedYet(resolveRunning: false))
        XCTAssertTrue(closed.contains("Resolve") && closed.contains("workflow apps"),
                      "with Resolve closed the honest instruction includes the manual path: \(closed)")
        let open = ZeroStatePolicy.zeroStateHint(.nothingTrackedYet(resolveRunning: true))
        XCTAssertTrue(open.contains("Start editing"), "got \(open)")
        XCTAssertNotEqual(closed, open, "the hint must reflect the user's actual situation")
    }

    func testEveryStateHasATitleAndAHint() {
        for state: ZeroStatePolicy.ZeroState in [.noProject,
                                          .nothingTrackedYet(resolveRunning: true),
                                          .nothingTrackedYet(resolveRunning: false)] {
            XCTAssertFalse(ZeroStatePolicy.zeroStateTitle(state).isEmpty)
            XCTAssertFalse(ZeroStatePolicy.zeroStateHint(state).isEmpty)
        }
    }
}
