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
        XCTAssertEqual(ProjectDetector.meaningfulName("26_08_AuroraEC"), "26_08_AuroraEC")
    }
}

/// The regression the awaitingProject rule nearly shipped with.
///
/// Every Adobe app is an anchor by default, and none of them is ever asked
/// what project it is on — only Resolve names projects. Keyed on "any
/// anchor", the rule held the clock forever in After Effects whenever
/// Resolve was closed: thirty mis-billed seconds traded for entire unbilled
/// days, which is the wrong direction twice over.
final class AdobeWorkStillRecordsTests: XCTestCase {

    private func frontmost(_ bundle: String) -> DetectionInput {
        var input = DetectionInput(
            frontmostBundleID: bundle,
            secondsSinceInput: 0,
            idleThreshold: 120,
            manuallyPaused: false,
            isAsleep: false,
            hasActiveProject: true)
        input.workAppPrefixes = DetectionInput.defaultWorkAppPrefixes
        // Resolve has answered before on this Mac, but is not running now, so
        // it has named nothing this launch.
        input.anchorCanNameProjects = true
        input.anchorNamedAProject = false
        return input
    }

    func testAfterEffectsWithResolveClosedStillRecords() {
        XCTAssertEqual(DetectionState.evaluate(frontmost("com.adobe.AfterEffects")), .recording,
                       "an Adobe-only day is billable; only Resolve is asked to name projects")
    }

    func testEveryDefaultAdobeAnchorStillRecords() {
        for bundle in DetectionInput.defaultWorkAppPrefixes
        where !DetectionInput.resolveBundleIDs.contains(bundle) {
            XCTAssertEqual(DetectionState.evaluate(frontmost(bundle)), .recording,
                           "\(bundle) must not wait for a project name it is never asked for")
        }
    }

    func testResolveItselfStillWaits() {
        XCTAssertEqual(DetectionState.evaluate(frontmost("com.blackmagic-design.DaVinciResolve")),
                       .paused(.awaitingProject),
                       "the app that CAN name a project still has to")
    }
}

/// "The process exited" is not "Resolve answered".
///
/// fuscript exits 0 and prints only its banner when `Resolve()` returns nil —
/// verified against the real binary on this Mac. Inferring reachability from
/// a clean exit marked a Resolve Free machine, or one with External Scripting
/// switched off, as "can be asked"; `anchorCanNameProjects` then latched
/// true, was persisted, and every launch afterwards held the clock waiting
/// for a project name that could never arrive. The escape hatch built for
/// exactly those machines was defeated by its own probe.
final class ScriptingReachabilityTests: XCTestCase {

    private let banner = """

        DaVinci Resolve Script Interpreter
        Copyright (C) 2005 - 2026 Blackmagic Design Pty. Ltd.

        """

    func testTheBannerAloneIsNotAnAnswer() {
        let out = ProjectDetector.parse(banner)
        XCTAssertFalse(out.ran, "no connection was made — this Mac cannot be asked")
        XCTAssertNil(out.name)
    }

    func testConnectedWithNothingOpenIsAnAnswerWithNoName() {
        let out = ProjectDetector.parse(banner + "CUTAWAY-REACHED\n")
        XCTAssertTrue(out.ran, "Resolve replied — waiting for a project is correct here")
        XCTAssertNil(out.name)
    }

    func testConnectedWithAProject() {
        let out = ProjectDetector.parse(banner + "CUTAWAY-REACHED\nCUTAWAY-NAME\t26_08_AuroraEC\n")
        XCTAssertTrue(out.ran)
        XCTAssertEqual(out.name, "26_08_AuroraEC")
    }

    /// The sentinel also fixes the old positional parse: a project name is
    /// whatever follows the tag, not whatever happens to be printed last.
    func testAProjectNamedLikeTheBannerIsStillRead() {
        let out = ProjectDetector.parse(
            banner + "CUTAWAY-REACHED\nCUTAWAY-NAME\tBlackmagic Design promo\n")
        XCTAssertEqual(out.name, "Blackmagic Design promo",
                       "the old parser filtered this line out as banner text")
    }

    func testAnErrorIsNotAProjectName() {
        let out = ProjectDetector.parse(banner + "CUTAWAY-REACHED\nCUTAWAY-NAME\tError: no project\n")
        XCTAssertTrue(out.ran)
        XCTAssertNil(out.name)
    }

    func testATerrorDocIsStillDetectable() {
        let out = ProjectDetector.parse(banner + "CUTAWAY-REACHED\nCUTAWAY-NAME\tTerror Doc\n")
        XCTAssertEqual(out.name, "Terror Doc", "contains 'error', is not an error")
    }
}
