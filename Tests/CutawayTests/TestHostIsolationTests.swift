import XCTest
@testable import Cutaway

/// A test run must not be able to reach the app the owner is using.
///
/// XCUIApplication attaches to a BUNDLE IDENTIFIER. The test host shipped the
/// same one as the app in /Applications, so every UI-test run terminated the
/// owner's running tracker — repeatedly, on 2026-09-10. Sessions closed
/// cleanly with a backup so no hours were lost, but the clock stopped each
/// time and had to be restarted by hand.
///
/// Prefs, StorePath and SessionLogger already quarantine on
/// XCTestConfigurationFilePath. This covers the paths that never go through
/// them: LaunchServices, TCC, and any UserDefaults access that bypasses
/// Prefs — AppKit's own window-frame autosave among them.
final class TestHostIsolationTests: XCTestCase {

    private func projectYML() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
    }

    func testTheDebugBuildIsADifferentAppToTheSystem() throws {
        let yml = try projectYML()
        guard let debugRange = yml.range(of: "        Debug:"),
              let releaseRange = yml.range(of: "        Release:") else {
            return XCTFail("could not find the Debug and Release config blocks")
        }
        let debugBlock = String(yml[debugRange.lowerBound..<releaseRange.lowerBound])
        XCTAssertTrue(debugBlock.contains("PRODUCT_BUNDLE_IDENTIFIER: com.vaneickelen.cutaway.debug"), """
            The Debug configuration must override PRODUCT_BUNDLE_IDENTIFIER. \
            Without it the test host IS the shipped app as far as macOS is \
            concerned, and a UI-test run terminates whatever the owner has \
            open.
            """)
    }

    /// And the running app must still be the real one — a Debug identifier
    /// leaking into Release would ship an app that cannot see its own
    /// Accessibility grant or its own store.
    func testTheShippedBuildKeepsTheRealIdentifier() throws {
        let yml = try projectYML()
        XCTAssertTrue(yml.contains("PRODUCT_BUNDLE_IDENTIFIER: com.vaneickelen.cutaway\n"),
                      "the base identifier, which Release inherits, must stay unqualified")
        guard let releaseRange = yml.range(of: "        Release:") else { return }
        let releaseBlock = String(yml[releaseRange.lowerBound...].prefix(1400))
        XCTAssertFalse(releaseBlock.contains("cutaway.debug"),
                       "the debug identifier must never reach a shipped build")
    }

    /// The quarantine that already existed is not replaced by this — both
    /// layers matter, and the Prefs one is what keeps a unit run out of the
    /// live defaults even when the bundle identifiers happen to match.
    func testPrefsQuarantineIsStillInPlace() {
        XCTAssertEqual(PrefsPolicy.suiteName(scenario: false, dataDir: nil, isTestRun: true),
                       "com.vaneickelen.cutaway.tests")
        XCTAssertEqual(PrefsPolicy.suiteName(scenario: true, dataDir: nil),
                       "com.vaneickelen.cutaway.scenario")
    }
}
