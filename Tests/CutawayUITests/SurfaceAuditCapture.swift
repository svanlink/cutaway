import XCTest

/// Photographs every surface the owner can reach, for design review.
///
/// The README capture takes three pictures. A design audit that only ever
/// looks at three surfaces reviews three surfaces — the sheets, the settings
/// and the permissions window had never been looked at, and it showed.
///
/// Skipped unless CUTAWAY_AUDIT is set. Each surface is attempted
/// independently: a missing one prints and the run continues, because a
/// half-finished contact sheet is still evidence.
final class SurfaceAuditCapture: XCTestCase {

    @MainActor
    func testPhotographEverySurface() throws {
        guard ProcessInfo.processInfo.environment["CUTAWAY_AUDIT"] != nil else {
            throw XCTSkip("set CUTAWAY_AUDIT=1 to capture the contact sheet")
        }
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cutaway-audit")
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        print("CUTAWAY_AUDIT_DIR=\(out.path)")

        let app = XCUIApplication()
        app.launchEnvironment["CUTAWAY_DEMO"] = "1"
        app.launchEnvironment["CUTAWAY_DATA_DIR"] = NSTemporaryDirectory() + "cutaway-audit-data"
        app.launch()

        func shoot(_ name: String, _ element: XCUIElement) {
            guard element.waitForExistence(timeout: 6) else {
                print("CAPTURE-MISS: \(name)"); return
            }
            Thread.sleep(forTimeInterval: 1.2)
            try? element.screenshot().pngRepresentation.write(to: out.appendingPathComponent("\(name).png"))
            print("CAPTURED: \(name)")
        }
        func escape() {
            XCUIElement.perform(withKeyModifiers: []) { app.typeKey(.escape, modifierFlags: []) }
            Thread.sleep(forTimeInterval: 0.6)
        }

        // 1. The main window, and the project switcher inside it.
        shoot("01-window", app.windows.firstMatch)
        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Nyx'")).firstMatch
        if title.waitForExistence(timeout: 4) {
            title.click()
            shoot("02-switcher", app.popovers.firstMatch)
            escape()
        } else { print("CAPTURE-MISS: 02-switcher (no title button)") }

        // 2. The sheets, each reached the way the owner reaches it.
        for (name, button) in [("03-project-sheet", "Edit project"),
                               ("04-add-day", "Add time for a day"),
                               ("05-add-session", "Add session…"),
                               ("06-edit-day", "Edit day…")] {
            let b = app.buttons[button].firstMatch
            guard b.waitForExistence(timeout: 4) else { print("CAPTURE-MISS: \(name)"); continue }
            b.click()
            shoot(name, app.sheets.firstMatch)
            escape()
        }

        // 3. Settings and the permissions window, which no capture has ever
        //    included and which are the two oldest screens in the app.
        XCUIElement.perform(withKeyModifiers: .command) { app.typeKey(",", modifierFlags: .command) }
        shoot("07-settings", app.windows.matching(NSPredicate(format: "title CONTAINS[c] 'Settings'")).firstMatch)

        // 4. The menu-bar panel.
        let pill = app.statusItems.firstMatch
        if pill.waitForExistence(timeout: 6) {
            pill.click()
            let panel = app.popovers.firstMatch
            if panel.waitForExistence(timeout: 4) {
                shoot("08-panel-first-run", panel)
                let notNow = panel.buttons["Not now"]
                if notNow.waitForExistence(timeout: 2) { notNow.click(); Thread.sleep(forTimeInterval: 0.8) }
                shoot("09-panel", panel)
            }
            escape()
        }
        app.terminate()
    }
}
