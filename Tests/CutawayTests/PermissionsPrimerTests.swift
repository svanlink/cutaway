import XCTest
@testable import Cutaway

final class PermissionsPrimerTests: XCTestCase {
    func testShownOnceOutsideScenarioMode() {
        XCTAssertTrue(PermissionsPrimerPolicy.shouldShow(alreadyShown: false, scenario: false))
        XCTAssertFalse(PermissionsPrimerPolicy.shouldShow(alreadyShown: true, scenario: false))
        XCTAssertFalse(PermissionsPrimerPolicy.shouldShow(alreadyShown: false, scenario: true),
                       "verification runs are never steered by onboarding")
    }

    func testTheStatementNamesWhatCutawayNeverDoes() {
        let s = PermissionsPrimerPolicy.statement
        for word in ["Screen Recording", "keystrokes", "leaves your Mac"] { XCTAssertTrue(s.contains(word), word) }
    }
}
