import XCTest

/// README screenshots, reproducibly: launches the demo build into a
/// quarantined store and writes element screenshots of the Stats window,
/// the pill and the open panel to its own temp dir, printing the path.
/// Skips unless CUTAWAY_CAPTURE is set (scripts/screenshots.sh sets it),
/// so the normal UI test run never writes files.
final class ScreenshotCaptureTests: XCTestCase {

    @MainActor
    func testCaptureReadmeScreenshots() throws {
        guard ProcessInfo.processInfo.environment["CUTAWAY_CAPTURE"] != nil else {
            throw XCTSkip("set CUTAWAY_CAPTURE=1 to capture")
        }
        // The runner may only write inside its own temp; the script reads
        // the path back out of the log.
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cutaway-screenshots")
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        print("CUTAWAY_CAPTURE_DIR=\(out.path)")

        let app = XCUIApplication()
        app.launchEnvironment["CUTAWAY_DEMO"] = "1"
        // Quarantine: without CUTAWAY_DATA_DIR the launched app opens the real
        // billing store.
        app.launchEnvironment["CUTAWAY_DATA_DIR"] = NSTemporaryDirectory() + "cutaway-screenshots"
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "the Stats window opens at launch")
        // Let the demo data render and the first tick land.
        Thread.sleep(forTimeInterval: 1.5)
        try window.screenshot().pngRepresentation.write(to: out.appendingPathComponent("stats.png"))

        let pill = app.statusItems.firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        try pill.screenshot().pngRepresentation.write(to: out.appendingPathComponent("pill.png"))

        pill.click()
        let panel = app.popovers.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        // The Debug build has no Accessibility grant, so the one-time offer
        // shows; the README panel is the everyday one, after "Not now".
        let notNow = panel.buttons["Not now"]
        if notNow.waitForExistence(timeout: 2) { notNow.click() }
        Thread.sleep(forTimeInterval: 1.0)
        try panel.screenshot().pngRepresentation.write(to: out.appendingPathComponent("panel.png"))
        app.terminate()
    }
}
