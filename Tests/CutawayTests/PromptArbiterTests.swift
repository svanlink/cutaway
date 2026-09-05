import XCTest
@testable import Cutaway

/// Two prompts can exist; one may be on screen. They cannot coincide by
/// state (idle needs recording, resume needs a manual pause) — this pins
/// that nothing later un-learns it.
final class PromptArbiterTests: XCTestCase {

    func testIdleWarningShowsWhileRecording() {
        let p = PromptArbiter.visible(idle: IdleWarning(secondsLeft: 12), resumeAsked: false,
                                      manuallyPaused: false, state: .recording)
        XCTAssertEqual(p, .idle(secondsLeft: 12))
    }

    func testResumePromptShowsOnlyWhileManuallyPaused() {
        XCTAssertEqual(PromptArbiter.visible(idle: nil, resumeAsked: true, manuallyPaused: true,
                                             state: .paused(.manual)), .resume)
        XCTAssertNil(PromptArbiter.visible(idle: nil, resumeAsked: true, manuallyPaused: false,
                                           state: .recording),
                     "an answered or auto-lifted pause takes its card with it")
    }

    func testNeverBoth() {
        // A stale idle warning handed in alongside a resume request: the
        // pause wins, because a paused clock cannot be about to idle-pause.
        let p = PromptArbiter.visible(idle: IdleWarning(secondsLeft: 5), resumeAsked: true,
                                      manuallyPaused: true, state: .paused(.manual))
        XCTAssertEqual(p, .resume)
        let q = PromptArbiter.visible(idle: IdleWarning(secondsLeft: 5), resumeAsked: false,
                                      manuallyPaused: false, state: .recording)
        XCTAssertEqual(q, .idle(secondsLeft: 5))
    }

    func testNothingWhenNothingIsAsked() {
        XCTAssertNil(PromptArbiter.visible(idle: nil, resumeAsked: false, manuallyPaused: false, state: .recording))
    }
}
