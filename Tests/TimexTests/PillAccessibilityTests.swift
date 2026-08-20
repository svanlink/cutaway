import XCTest
@testable import Cutaway

/// The pill is the whole app for most of the day, and it used to tell a
/// screen reader only "Recording" — not the number it exists to show, not
/// which project that number belongs to, and nothing at all about the two
/// messages that replace the readout on screen.
final class PillAccessibilityTests: XCTestCase {

    private func label(project: String? = "Nyx Fashion Film", recording: Bool = true,
                       seconds: TimeInterval = 8047, banked: String? = nil,
                       hint: String? = nil) -> String {
        PillView.accessibilityLabel(project: project, isRecording: recording,
                                    seconds: seconds, banked: banked, pausedHint: hint)
    }

    func testItSaysTheStateTheTimeAndTheProject() {
        let l = label()
        XCTAssertTrue(l.contains("recording"), l)
        XCTAssertTrue(l.contains("2 hours 14 minutes"), l)
        XCTAssertTrue(l.contains("Nyx Fashion Film"), "which project is not a detail: \(l)")
    }

    func testPausedSaysSo() {
        XCTAssertTrue(label(recording: false).contains("paused"))
    }

    func testNoProjectIsItsOwnState() {
        let l = label(project: nil)
        XCTAssertEqual(l, "Cutaway — no project selected")
        XCTAssertFalse(l.contains("recording"), "nothing is being tracked — do not imply it is")
        XCTAssertEqual(label(project: ""), "Cutaway — no project selected",
                       "an empty name is no project, not a project called nothing")
    }

    /// The flash and the hint REPLACE the readout on screen. Announcing a
    /// time that is not being displayed would describe a pill that does not
    /// exist.
    func testTheBankedFlashIsAnnouncedInsteadOfTheTime() {
        let l = label(banked: "✓ 47 min banked")
        XCTAssertTrue(l.contains("47 min banked"), l)
        XCTAssertFalse(l.contains("✓"), "a checkmark glyph is not a word: \(l)")
        XCTAssertFalse(l.contains("2 hours"), "the pill is not showing the time right now")
        XCTAssertTrue(l.contains("Nyx Fashion Film"))
    }

    func testTheForgottenPauseHintIsAnnounced() {
        let l = label(recording: false, hint: "still paused")
        XCTAssertTrue(l.contains("still paused"), l)
        XCTAssertFalse(l.contains("2 hours"))
    }

    /// A screen reader spelling out "2:14:07" is worse than no clock at all.
    func testDurationsAreSpokenNotSpelled() {
        XCTAssertEqual(PillView.spokenDuration(8047), "2 hours 14 minutes")
        XCTAssertEqual(PillView.spokenDuration(3600), "1 hour")
        XCTAssertEqual(PillView.spokenDuration(60), "1 minute")
        XCTAssertEqual(PillView.spokenDuration(7200), "2 hours")
        XCTAssertEqual(PillView.spokenDuration(0), "under a minute",
                       "never 'zero hours zero minutes'")
        XCTAssertEqual(PillView.spokenDuration(45), "under a minute")
        XCTAssertEqual(PillView.spokenDuration(-5), "under a minute", "and never negative")
    }
}
