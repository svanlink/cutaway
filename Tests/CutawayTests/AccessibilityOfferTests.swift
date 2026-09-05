import XCTest
@testable import Cutaway

/// A permission prompt someone has already declined is nagware. This offer
/// gets exactly one chance, and only when it can actually mean something.
@MainActor
final class AccessibilityOfferTests: XCTestCase {

    private func offer(granted: Bool = false, dismissed: Bool = false,
                       hasProject: Bool = true, zeroState: Bool = false) -> Bool {
        AccessibilityOfferPolicy.shouldOfferAccessibility(granted: granted, dismissed: dismissed,
                                          hasProject: hasProject, zeroStateShowing: zeroState)
    }

    func testOffersOnceWhenItCanActuallyHelp() {
        XCTAssertTrue(offer(), "a project exists, permission is missing, nothing else is asking")
    }

    func testNeverWhenAlreadyGranted() {
        XCTAssertFalse(offer(granted: true), "asking for what you already have is noise")
    }

    func testNeverAgainAfterDecline() {
        XCTAssertFalse(offer(dismissed: true), "'not now' means not again")
        XCTAssertFalse(offer(granted: true, dismissed: true))
    }

    func testNeverBeforeThereIsAProject() {
        XCTAssertFalse(offer(hasProject: false),
                       "nothing to detect for yet — the ask would be meaningless")
    }

    func testNeverStackedOnAZeroState() {
        XCTAssertFalse(offer(zeroState: true),
                       "the zero state is already asking for attention; one ask at a time")
    }

    func testDismissalPersists() {
        let key = "accessibilityOfferDismissed"
        let original = Prefs.bool(forKey: key)
        defer { Prefs.set(original, forKey: key) }

        Prefs.set(false, forKey: key)
        XCTAssertTrue(offer(dismissed: Prefs.bool(forKey: key)))
        // What the "Not now" button does.
        Prefs.set(true, forKey: key)
        XCTAssertFalse(offer(dismissed: Prefs.bool(forKey: key)),
                       "the decline must survive a relaunch, not just a render")
    }
}
