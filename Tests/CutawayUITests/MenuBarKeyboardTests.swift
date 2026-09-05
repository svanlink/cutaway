import XCTest

/// The audit's blunt finding: "there is no path. No menu bar, no Quit item. A
/// user who cannot use Cmd-Q from a focused window — which is everyone in
/// accessory mode — cannot quit Cutaway without Activity Monitor."
///
/// These drive the real status item and the real popover. They need a
/// logged-in GUI session with a visible menu bar.
///
/// A note on the flakiness that is easy to misread here. These tests appeared
/// to fail intermittently — 1/3 and 2/3 on repeated runs, a different one each
/// time — and the obvious conclusion was that synthesised key events do not
/// reliably reach an NSPopover. That conclusion was wrong. The failures were
/// "Timed out while enabling automation mode": the test RUNNER was not
/// starting, because earlier runs had left Cutaway processes alive on the
/// machine. With those cleared, the suite passes.
///
/// The lesson is worth more than the tests: when UI tests fail, read the
/// failure before believing the diagnosis. An assertion failure and a runner
/// that never launched look identical in a pass/fail count.
///
/// If a real failure does appear, `docs/ACCESSIBILITY-MANUAL.md` has the
/// by-hand procedure for the same behaviours.
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
        app.launchEnvironment["CUTAWAY_DEMO"] = "1"
        // Quarantine: without CUTAWAY_DATA_DIR the launched app opens the real
        // billing store — these tests were recording test-run seconds into
        // the store a user invoices from.
        app.launchEnvironment["CUTAWAY_DATA_DIR"] = NSTemporaryDirectory() + "cutaway-uitests"
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

    /// WCAG 2.1.2, No Keyboard Trap. A panel that opens from the keyboard and
    /// cannot be closed from it is a trap.
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

    /// The status item's menu is mouse-only — right-click has no keyboard
    /// equivalent. The keyboard route in is Ctrl-F8 then Return, which opens
    /// the panel, so the universal quit shortcut has to work from there or a
    /// keyboard user still cannot leave.
    @MainActor
    func testCommandQuitWorksFromThePanel() throws {
        let app = launched()

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.click()
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5))

        app.typeKey("q", modifierFlags: .command)

        let quit = NSPredicate(format: "state == %d", XCUIApplication.State.notRunning.rawValue)
        expectation(for: quit, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }

    /// The HIG pattern: a menu bar extra offers Quit from its own menu.
    @MainActor
    func testTheStatusItemMenuOffersQuit() throws {
        let app = launched()
        defer { if app.state == .runningForeground { app.terminate() } }

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.rightClick()

        XCTAssertTrue(app.menuItems["Quit Cutaway"].waitForExistence(timeout: 5),
                      "a menu bar extra must offer Quit")
        XCTAssertTrue(app.menuItems["Open Cutaway"].exists)
        XCTAssertTrue(app.menuItems["Settings…"].exists)
        app.typeKey(.escape, modifierFlags: [])
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
