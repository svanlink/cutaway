import XCTest
@testable import Cutaway

/// Opening Resolve is not the same as opening a project.
///
/// Live incident, 2026-09-09 08:21:52 on the owner's Mac. Resolve was
/// launched with no project open. The clock started the instant Resolve
/// became frontmost, against whatever project had been selected the previous
/// day. One second later Tier 1 answered `name=nil` — Resolve saying it had
/// nothing open — and the app carried on regardless. Thirty seconds were
/// written to the wrong client before the mismatch card appeared:
///
///     08:21:52  recording
///     08:21:53  tier1  name=nil
///     08:22:20  tier1  name=Untitled Project
///     08:22:23  paused(projectMismatch)  session-closed active=29s
///
/// Small money, and precisely the class this app exists to prevent: it
/// billed an assumption. An anchor that has not said which project it is on
/// has not established a work context.
final class AnchorWithoutAProjectTests: XCTestCase {

    private func resolveFrontmost(anchorNamedProject: Bool,
                                  tierOneAvailable: Bool = true) -> DetectionInput {
        var input = DetectionInput(
            frontmostBundleID: "com.blackmagic-design.DaVinciResolve",
            secondsSinceInput: 0,
            idleThreshold: 120,
            manuallyPaused: false,
            isAsleep: false,
            hasActiveProject: true)
        input.workAppPrefixes = DetectionInput.resolveBundleIDs
        input.anchorNamedAProject = anchorNamedProject
        input.anchorCanNameProjects = tierOneAvailable
        return input
    }

    func testTheClockWaitsUntilResolveSaysWhichProject() {
        XCTAssertEqual(DetectionState.evaluate(resolveFrontmost(anchorNamedProject: false)),
                       .paused(.awaitingProject),
                       "Resolve is open with nothing loaded — there is no project to bill")
    }

    func testItRecordsAsSoonAsResolveNamesOne() {
        XCTAssertEqual(DetectionState.evaluate(resolveFrontmost(anchorNamedProject: true)),
                       .recording)
    }

    /// The escape hatch. On a free edition, or with External Scripting off,
    /// Tier 1 can never answer — holding forever would make the app useless
    /// rather than careful. There, the previous behaviour stands.
    func testAMachineThatCanNeverAskStillRecords() {
        XCTAssertEqual(
            DetectionState.evaluate(resolveFrontmost(anchorNamedProject: false,
                                                     tierOneAvailable: false)),
            .recording,
            "if Resolve cannot be asked, waiting for an answer never ends")
    }

    /// Manual pause, sleep and a known mismatch all still outrank it.
    func testTheStrongerPausesStillWin() {
        var input = resolveFrontmost(anchorNamedProject: false)
        input.manuallyPaused = true
        XCTAssertEqual(DetectionState.evaluate(input), .paused(.manual))

        var mismatch = resolveFrontmost(anchorNamedProject: false)
        mismatch.projectMismatch = true
        XCTAssertEqual(DetectionState.evaluate(mismatch), .paused(.projectMismatch),
                       "a known wrong project is more specific than an unknown one")
    }

    /// "Untitled Project" is Resolve's placeholder for nothing loaded. It is
    /// not a project name, and it must never become one: it is how a stray
    /// project called "Untitled Project" got created once already.
    func testResolvesPlaceholderIsNotAProjectName() {
        XCTAssertNil(ProjectDetector.meaningfulName("Untitled Project"))
        XCTAssertNil(ProjectDetector.meaningfulName("  untitled project  "))
        XCTAssertNil(ProjectDetector.meaningfulName(""))
        XCTAssertEqual(ProjectDetector.meaningfulName("26_08_RichemontEC"), "26_08_RichemontEC")
    }
}
