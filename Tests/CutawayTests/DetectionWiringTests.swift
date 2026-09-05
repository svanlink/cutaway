import XCTest
@testable import Cutaway

/// The stale-Tier-1 race guard vanished once without a single test going
/// red: ManualIntentTests exercise the struct, and nothing checked that the
/// struct was still WIRED into the detection path. A part that is tested
/// but not installed passes every test it has. These read the source, the
/// same way DesignTokenGuardTests does, because no unit test can reach a
/// closure inside AppModel.init.
final class DetectionWiringTests: XCTestCase {

    private var appModelSource: String {
        get throws {
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<3 { root.deleteLastPathComponent() }
            return try String(contentsOf: root.appendingPathComponent("Sources/Cutaway/AppModel.swift"),
                              encoding: .utf8)
        }
    }

    func testTheStaleTier1GuardIsActuallyWired() throws {
        let source = try appModelSource
        XCTAssertTrue(source.contains("let startedAt = self.intent.token"),
                      "the Tier-1 request no longer stamps the intent token before starting")
        XCTAssertTrue(source.contains("hasMovedSince(startedAt)"),
                      "a stale Tier-1 answer can overrule a newer manual choice again")
    }

    func testTier1AttemptsLeaveAForensicTrace() throws {
        XCTAssertTrue(try appModelSource.contains("logDetection(\"tier1\""),
                      "an attempt that returns nothing must not vanish without a log line")
    }

    func testManualSelectionStillCountsAsIntent() throws {
        XCTAssertTrue(try appModelSource.contains("intent.userChose()"),
                      "selectManually must bump the token or the guard guards nothing")
    }
}
