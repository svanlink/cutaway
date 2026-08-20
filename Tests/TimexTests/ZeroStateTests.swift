import XCTest
@testable import Cutaway

/// "Why isn't this counting?" is the first question a new user has, and the
/// answer used to live only in the README. These lock the branches — in
/// particular that a quiet afternoon is not mistaken for an empty app.
@MainActor
final class ZeroStateTests: XCTestCase {

    func testNoProjectOutranksEverythingElse() {
        XCTAssertEqual(
            AppModel.zeroState(hasProject: false, trackedSeconds: 0,
                               isRecording: false, resolveRunning: true),
            .noProject,
            "with nothing to attribute time to, Resolve being open is irrelevant")
    }

    func testFreshProjectExplainsWhatStartsTheClock() {
        XCTAssertEqual(
            AppModel.zeroState(hasProject: true, trackedSeconds: 0,
                               isRecording: false, resolveRunning: false),
            .nothingTrackedYet(resolveRunning: false))
        XCTAssertEqual(
            AppModel.zeroState(hasProject: true, trackedSeconds: 0,
                               isRecording: false, resolveRunning: true),
            .nothingTrackedYet(resolveRunning: true))
    }

    func testRecordedHistoryIsNotAZeroState() {
        XCTAssertNil(
            AppModel.zeroState(hasProject: true, trackedSeconds: 3600,
                               isRecording: false, resolveRunning: false),
            "a quiet afternoon on a project with history is not an empty app")
    }

    func testRecordingIsNeverAZeroState() {
        XCTAssertNil(
            AppModel.zeroState(hasProject: true, trackedSeconds: 0,
                               isRecording: true, resolveRunning: true),
            "the very first seconds are already being tracked — say nothing")
    }

    func testHintNeverPromisesDetectionThatCannotHappen() {
        let closed = AppModel.zeroStateHint(.nothingTrackedYet(resolveRunning: false))
        XCTAssertTrue(closed.contains("Resolve") && closed.contains("workflow apps"),
                      "with Resolve closed the honest instruction includes the manual path: \(closed)")
        let open = AppModel.zeroStateHint(.nothingTrackedYet(resolveRunning: true))
        XCTAssertTrue(open.contains("Start editing"), "got \(open)")
        XCTAssertNotEqual(closed, open, "the hint must reflect the user's actual situation")
    }

    func testEveryStateHasATitleAndAHint() {
        for state: AppModel.ZeroState in [.noProject,
                                          .nothingTrackedYet(resolveRunning: true),
                                          .nothingTrackedYet(resolveRunning: false)] {
            XCTAssertFalse(AppModel.zeroStateTitle(state).isEmpty)
            XCTAssertFalse(AppModel.zeroStateHint(state).isEmpty)
        }
    }
}
