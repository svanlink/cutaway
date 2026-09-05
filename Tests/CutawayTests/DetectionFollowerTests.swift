import XCTest
@testable import Cutaway

/// The app's stated principle is that explicit user intent outranks
/// automation — it is why manual pause is sacred. Auto-switch used to break
/// it on a five-second timer: it re-asserted whatever Resolve had loaded, so
/// a manual switch could not be held and work done for one project with
/// another open in Resolve billed to the wrong one.
final class DetectionFollowerTests: XCTestCase {

    func testFirstSightingIsAlwaysATransition() {
        var f = DetectionFollower()
        XCTAssertEqual(f.observe("Nyx Fashion Film"), "Nyx Fashion Film",
                       "a fresh install must adopt whatever is already open")
    }

    /// The defect, as a test: detect A, the user picks B, Resolve keeps
    /// reporting A. The user's choice has to survive.
    func testPollingTheSameProjectNeverMovesAttribution() {
        var f = DetectionFollower()
        XCTAssertEqual(f.observe("Alpina"), "Alpina")
        // ...user manually selects a different project here...
        for _ in 0..<100 {
            XCTAssertNil(f.observe("Alpina"),
                         "Resolve has not moved — this is not new information")
        }
    }

    func testARealChangeInResolveStillFollows() {
        var f = DetectionFollower()
        _ = f.observe("Alpina")
        for _ in 0..<10 { XCTAssertNil(f.observe("Alpina")) }
        XCTAssertEqual(f.observe("Nyx"), "Nyx", "Resolve moved — attribution follows")
        XCTAssertNil(f.observe("Nyx"))
        XCTAssertEqual(f.observe("Alpina"), "Alpina", "and back again")
    }

    func testTierDisagreementIsNotATransition() {
        var f = DetectionFollower()
        _ = f.observe("Nyx Fashion Film")
        XCTAssertNil(f.observe("  nyx fashion film  "),
                     "case and whitespace drift between tiers is not a project change")
        XCTAssertNil(f.observe("NYX FASHION FILM"))
    }

    func testEmptyNamesAreIgnoredEntirely() {
        var f = DetectionFollower()
        _ = f.observe("Nyx")
        XCTAssertNil(f.observe(""))
        XCTAssertNil(f.observe("   "))
        XCTAssertNil(f.observe("Nyx"), "a blank reading must not fake a transition")
    }

    func testResetMakesTheNextSightingFresh() {
        var f = DetectionFollower()
        _ = f.observe("Nyx")
        f.reset()
        XCTAssertEqual(f.observe("Nyx"), "Nyx", "Resolve relaunching is a fresh transition")
    }

    func testNameMatchingIsTheSameRuleUsedForDeduplication() {
        XCTAssertTrue(ProjectName.matches("Café Noir", "cafe noir"))
        XCTAssertTrue(ProjectName.matches(" Nyx ", "nyx"))
        XCTAssertFalse(ProjectName.matches("Nyx", "Nyx 2"))
    }
}
