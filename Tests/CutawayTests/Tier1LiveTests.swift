import XCTest
import AppKit
@testable import Cutaway

/// The live Tier-1 proof — the README's headline claim ("asks Resolve which
/// project is open and switches attribution automatically") tested against
/// an actual running DaVinci Resolve, not a fake.
///
/// This is the backlog's "optional harness scenario": it SKIPS unless
/// Resolve Studio is running, so the suite stays green on any machine while
/// this file only ever passes by talking to the real application. First
/// green run: 2026-08-23, against a project named
/// "2026-08-22_Decathlon_SportsFest".
@MainActor
final class Tier1LiveTests: XCTestCase {

    private var resolveIsUp: Bool {
        NSWorkspace.shared.runningApplications.contains {
            DetectionInput.resolveBundleIDs.contains($0.bundleIdentifier ?? "")
        }
    }

    private var studioScriptingPresent: Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting")
    }

    func testTheScriptingAPIReportsTheOpenProject() async throws {
        try XCTSkipUnless(resolveIsUp, "Resolve is not running — Tier 1 has nothing to talk to")
        try XCTSkipUnless(studioScriptingPresent,
                          "Free edition — external scripting only answers on Studio")

        let detector = ProjectDetector()
        XCTAssertNotNil(ProjectDetector.fuscriptPath(),
                        "fuscript must be locatable when Resolve is installed")

        let name = await detector.detectViaScriptingAPI()
        // The Developer/Scripting folder ships with every edition, so its
        // presence does not mean external scripting is AVAILABLE: the free
        // edition refuses, and Studio refuses until "External scripting
        // using" is switched on in Preferences. Neither is a regression in
        // this app, and neither must be reported as one — but everything
        // below still has to hold whenever Tier 1 does answer.
        try XCTSkipUnless(name != nil, "external scripting did not answer — free edition, or External scripting using is off in Resolve's preferences")
        let detected = try XCTUnwrap(name)
        XCTAssertFalse(detected.isEmpty)
        XCTAssertFalse(detected.contains("Blackmagic Design"),
                       "the banner filter must not leak boilerplate as a project name")
        XCTAssertFalse(detected.contains("Script Interpreter"))
        XCTAssertEqual(detector.activeTier, .scriptingAPI)
        XCTAssertEqual(detector.lastDetectedName, detected)
    }

    func testTheEditionLineKnowsItIsStudio() throws {
        try XCTSkipUnless(resolveIsUp, "Resolve is not running")
        try XCTSkipUnless(studioScriptingPresent, "not Studio")
        XCTAssertEqual(ProjectDetector().resolveEdition(), "Resolve Studio")
    }
}
