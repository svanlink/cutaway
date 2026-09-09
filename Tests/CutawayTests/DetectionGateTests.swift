import XCTest
@testable import Cutaway

/// Detection must be able to observe its way out of every state it can cause.
///
/// The allow-list this replaced trapped itself twice in two days. Both times
/// a pause state was introduced whose only release came from the detection
/// the pause switched off, and both times every unit test stayed green
/// because they call `DetectionState.evaluate` directly and never go through
/// the gate.
final class DetectionGateTests: XCTestCase {

    /// The whole point: a state that detection can cause must be a state
    /// detection still runs in, or the app cannot recover without a relaunch.
    func testEveryPauseDetectionCanCauseIsStillObserved() {
        for reason in [PauseReason.noProject, .projectMismatch, .awaitingProject] {
            XCTAssertTrue(ProjectAutoSwitcher.observes(.paused(reason)),
                          "\(reason) is set by detection — only detection can clear it")
        }
        XCTAssertTrue(ProjectAutoSwitcher.observes(.recording))
    }

    /// Idle and not-frontmost are not detection's doing, but Resolve can
    /// change project while the clock is parked in either — and coming back
    /// to a stale answer bills the previous project until the next poll.
    func testTheWorldIsStillWatchedWhileTheClockIsParked() {
        XCTAssertTrue(ProjectAutoSwitcher.observes(.paused(.inputIdle)))
        XCTAssertTrue(ProjectAutoSwitcher.observes(.paused(.notFrontmost)))
    }

    /// The two that are switched off on purpose. A manual pause is sacred —
    /// automation must not talk the owner out of it — and a sleeping Mac has
    /// nothing to say.
    func testAManualPauseAndSleepAreLeftAlone() {
        XCTAssertFalse(ProjectAutoSwitcher.observes(.paused(.manual)))
        XCTAssertFalse(ProjectAutoSwitcher.observes(.paused(.systemSleep)))
    }

    /// Written against the enum itself, so a pause reason added next year is
    /// observed by default and has to be excluded deliberately.
    func testANewPauseReasonIsObservedUnlessDeliberatelyExcluded() {
        let sacred: [PauseReason] = [.manual, .systemSleep]
        for reason in PauseReason.allCases where !sacred.contains(reason) {
            XCTAssertTrue(ProjectAutoSwitcher.observes(.paused(reason)),
                          "\(reason) was added without deciding whether detection can clear it")
        }
    }
}
