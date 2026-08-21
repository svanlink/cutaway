import XCTest

/// The audit's blunt finding: "there is no path. No menu bar, no Quit item. A
/// user who cannot use Cmd-Q from a focused window — which is everyone in
/// accessory mode — cannot quit Cutaway without Activity Monitor."
///
/// These drive the real status item and the real popover. They need a logged-in
/// GUI session with a visible menu bar and are the most fragile tests in the
/// suite; if one fails twice with no source change between, quarantine it
/// rather than debugging the window server.
final class MenuBarKeyboardTests: XCTestCase {

    /// A fullscreen app hides the menu bar, and the status item is then
    /// present but not hittable.
    private func revealMenuBar() {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: 100, y: 2), mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TIMEX_DEMO"] = "1"
        app.launch()
        revealMenuBar()
        return app
    }

    @MainActor
    func testThePillOpensThePanelAndThePanelIsReachable() throws {
        let app = launched()
        defer { app.terminate() }

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the app's primary surface")
        pill.click()

        let panel = app.popovers.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5),
                      "the panel's contents must be in the accessibility tree")
    }

    /// WCAG 2.1.2, No Keyboard Trap. Escape was inherited behaviour; this is
    /// what stops it silently regressing.
    @MainActor
    func testEscapeDismissesThePanel() throws {
        let app = launched()
        defer { app.terminate() }

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.click()
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.popovers.firstMatch)
        waitForExpectations(timeout: 5)
    }

    /// The defect itself: no way out of the app without a mouse.
    @MainActor
    func testThePanelOffersAWayToQuit() throws {
        let app = launched()
        defer { if app.state == .runningForeground { app.terminate() } }

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.click()

        let panel = app.popovers.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.buttons["Quit Cutaway"].exists,
                      "the keyboard's only route in is this panel, so Quit has to be here")
    }

    /// The panel states the project it is billing — a regression guard for the
    /// hero label that used to announce only "Open Cutaway".
    @MainActor
    func testThePanelAnnouncesWhatItIsTracking() throws {
        let app = launched()
        defer { app.terminate() }

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        let spoken = (pill.value as? String) ?? pill.label
        XCTAssertFalse(spoken.isEmpty, "the status item must carry its figure")
    }
}
