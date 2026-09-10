import XCTest
@testable import Cutaway

/// The clock's own promises, each pinned by the property rather than by the
/// line that was once wrong.
final class DetectionIllogicTests: XCTestCase {

    // MARK: - The anchor list means what it says

    /// `anchorAppRunning` used to union Resolve's bundle IDs onto whatever it
    /// was given, so a project that deliberately excluded Resolve reported an
    /// anchor running because Resolve was open rendering something else — and
    /// the satellite window then sustained the clock for its full twenty
    /// minutes after the real anchor closed.
    func testTheProbeAsksAboutTheListItWasGivenAndNothingElse() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Cutaway/Detection/SystemProbes.swift"), encoding: .utf8)
        let body = try XCTUnwrap(source.range(of: "func anchorAppRunning"))
        let fn = String(source[body.lowerBound...].prefix(900))
        XCTAssertFalse(fn.contains("prefixes + DetectionInput.resolveBundleIDs"),
                       "a probe does not get a vote on what this project's anchors are")
    }

    // MARK: - Tier 2 title parsing

    /// Resolve appends the current page. Tier 1 asks the API and gets the
    /// bare name, so a page suffix means the two tiers can never agree.
    func testATrailingPageNameIsNotPartOfTheProjectName() {
        for page in ["Color", "Edit", "Fusion", "Fairlight", "Deliver", "Media", "Cut", "colour"] {
            XCTAssertEqual(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - Nyx - \(page)"),
                           "Nyx", "the \(page) page is a screen, not a project")
        }
    }

    /// A multi-part project name keeps every part of itself.
    func testAProjectNameContainingASeparatorSurvivesWhole() {
        XCTAssertEqual(
            ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - 2026-08-2 - OpeningFilm"),
            "2026-08-2 - OpeningFilm")
        XCTAssertEqual(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - Nyx"), "Nyx")
    }

    /// A window that names no project still names no project.
    func testABareResolveTitleNamesNothing() {
        XCTAssertNil(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve"))
        XCTAssertNil(ProjectDetector.projectName(fromWindowTitle: "DaVinci Resolve - Color"),
                     "a page alone is not a project")
    }

    // MARK: - Tier 1 cadence

    /// `anchorNamedAProject` has one writer — this poll — and Tier 2 cannot
    /// substitute, because a window titled just "DaVinci Resolve" parses to
    /// nil. Backing off to two minutes while Resolve is in front meant
    /// closing a project billed up to two minutes to the one just closed,
    /// and opening one held the clock through two minutes of real editing.
    func testTierOnePollsFastWhileResolveIsInFront() {
        var fastest = Int.max
        var last = 0
        var schedule = DetectionSchedule()
        for tick in 1...600 {
            schedule.advance()
            guard schedule.runsTier1(accessibilityGranted: true, anchorIsFrontmost: true) else { continue }
            // Past the deliberate early poll at `tier1FirstAt`, which exists
            // so a fresh install picks the open project up in seconds.
            guard tick > DetectionSchedule.tier1FirstAt else { last = tick; continue }
            if last > DetectionSchedule.tier1FirstAt { fastest = min(fastest, tick - last) }
            last = tick
        }
        XCTAssertEqual(fastest, DetectionSchedule.tier1WithoutAccessibility,
                       "the tier being waited on does not back off")
    }

    /// And still backs off when it is not the one being waited on.
    func testTierOneBacksOffWhenResolveIsNotInFront() {
        var schedule = DetectionSchedule()
        var runs = 0
        for _ in 1...600 {
            schedule.advance()
            if schedule.runsTier1(accessibilityGranted: true, anchorIsFrontmost: false) { runs += 1 }
        }
        XCTAssertLessThanOrEqual(runs, 600 / DetectionSchedule.tier1WithAccessibility + 1,
                                 "fuscript is the app's heaviest periodic cost")
    }
}

/// Transitions that used to leave a session open, and hard boundaries that
/// were not observed at all.
@MainActor
final class ClockBoundaryTests: XCTestCase {

    /// A bridge gap that meets ANY pause closes the session.
    ///
    /// The close was written for `.inputIdle` alone, so recording → detour
    /// (gap opens) → Resolve switches project → `.paused(.projectMismatch)`
    /// matched no case: nothing closed, nothing cleared the gap, and the
    /// expiry sweep is gated on `notFrontmost`. The session stayed open until
    /// the midnight force-close, putting its `end` hours after its last
    /// active second — and `DaySplitter` divides active seconds by wall-clock
    /// span.
    func testEveryPauseReasonClosesAnOpenBridge() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Cutaway/Detection/DetectionEngine.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("case .paused where awayGapStart != nil:"),
                      "the rule is 'a bridge is open and we are not recording', "
                    + "not a list of the pause reasons someone thought of")
        XCTAssertFalse(source.contains("case .paused(.inputIdle) where awayGapStart != nil:"),
                       "enumerating the reasons was the defect")
    }

    /// Fast user switching is a hard boundary.
    ///
    /// Every signal the engine has lies during another user's session: the
    /// frontmost cache does not update, our Resolve is still running, and the
    /// HID idle counter is machine-wide, so the other person's typing keeps
    /// it near zero. The clock recorded, unbounded, invisibly.
    func testTheEngineObservesTheSessionGoingInactive() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Cutaway/Detection/DetectionEngine.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("sessionDidResignActiveNotification"),
                      "another user's session must stop this one's clock")
        XCTAssertTrue(source.contains("sessionDidBecomeActiveNotification"),
                      "and coming back must release it")
    }
}
