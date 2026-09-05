import XCTest
@testable import Cutaway

/// `.recording` was opaque: identical whether Resolve was in front or a
/// browser was holding the clock up inside the research window. That window
/// expires silently, so an editor researching in Chrome learned about it only
/// by noticing the timer had stopped some time ago.
final class RecordingSourceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let window: TimeInterval = 1200

    private func input(front: String, satelliteWindowOpen: Bool = true) -> DetectionInput {
        var i = DetectionInput(frontmostBundleID: front, secondsSinceInput: 0,
                               idleThreshold: 120, manuallyPaused: false, isAsleep: false,
                               hasActiveProject: true,
                               workAppPrefixes: DetectionInput.defaultWorkAppPrefixes)
        i.satellitePrefixes = DetectionInput.defaultSatellitePrefixes
        i.satelliteWindowOpen = satelliteWindowOpen
        return i
    }

    private func source(front: String, lastAnchor: Date?) -> RecordingSource? {
        RecordingSource.evaluate(state: .recording, input: input(front: front),
                                 lastAnchorActive: lastAnchor, window: window, now: now)
    }

    func testResolveInFrontNeedsNoExplanation() {
        XCTAssertEqual(source(front: DetectionInput.resolveBundleIDs[0], lastAnchor: now), .anchor)
        XCTAssertEqual(source(front: "com.adobe.AfterEffects.2026", lastAnchor: now), .anchor)
        XCTAssertFalse(RecordingSource.anchor.isTimeLimited,
                       "anchor recording stops when the work does, not on a timer")
    }

    func testASatelliteReportsTheTimeItHasLeft() {
        let fiveMinutesIn = now.addingTimeInterval(-300)
        let s = source(front: "com.google.Chrome", lastAnchor: fiveMinutesIn)
        XCTAssertEqual(s, .satellite(secondsLeft: 900), "20 min window, 5 min used")
        XCTAssertTrue(s?.isTimeLimited == true)
    }

    func testTheCountdownNeverPromisesTimeItDoesNotHave() {
        XCTAssertEqual(RecordingSource.satellite(secondsLeft: 119).label,
                       "Research time · 1 min left", "rounds down: 1:59 is not 2 minutes")
        XCTAssertEqual(RecordingSource.satellite(secondsLeft: 59).label,
                       "Research time · under a minute left")
        XCTAssertEqual(RecordingSource.satellite(secondsLeft: 0).label,
                       "Research time · under a minute left")
    }

    func testAnchorHasNothingToSay() {
        XCTAssertNil(RecordingSource.anchor.label,
                     "a line the user cannot act on is noise")
    }

    func testNotRecordingHasNoSource() {
        for state: DetectionState in [.paused(.manual), .paused(.inputIdle),
                                      .paused(.systemSleep), .paused(.notFrontmost)] {
            XCTAssertNil(RecordingSource.evaluate(state: state,
                                                  input: input(front: "com.google.Chrome"),
                                                  lastAnchorActive: now, window: window, now: now))
        }
    }

    func testASatelliteWithNoAnchorHistoryReportsNothing() {
        XCTAssertNil(source(front: "com.google.Chrome", lastAnchor: nil),
                     "without an anchor there is no window to count down")
    }

    func testAnExhaustedWindowClampsAtZeroRatherThanGoingNegative() {
        let longAgo = now.addingTimeInterval(-5000)
        XCTAssertEqual(source(front: "com.google.Chrome", lastAnchor: longAgo),
                       .satellite(secondsLeft: 0))
    }

    func testAnUnknownAppIsNeitherAnchorNorSatellite() {
        XCTAssertNil(source(front: "com.spotify.client", lastAnchor: now))
    }
}
