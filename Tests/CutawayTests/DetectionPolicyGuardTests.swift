import XCTest
@testable import Cutaway

/// Three policies that live in one word each, and that a future edit could
/// undo without any test going red.
///
/// These assert PATTERNS across the whole source tree, not the exact text of
/// a line that was once wrong. A guard that pins yesterday's offender proves
/// only that yesterday cannot recur; the class recurs somewhere else, which
/// is how the same un-localized-string bug shipped three times.
final class DetectionPolicyGuardTests: XCTestCase {

    private func sources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CutawayTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/Cutaway")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 40, "the source tree was not found")
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Presence means a human, not an event.
    ///
    /// `.combinedSessionState` counts CGEvents posted by any process, so a
    /// jiggler, a macro pad or a screen-sharing session keeps the clock
    /// running with nobody at the desk. Only the HID table sees hardware.
    func testIdleIsReadFromHardwareNotFromAnyPostedEvent() throws {
        for file in try sources() {
            XCTAssertFalse(file.text.contains("combinedSessionState"),
                           "\(file.name) reads idle from the combined event table — "
                         + "synthetic events would bill absent time. Use .hidSystemState.")
        }
    }

    /// Client names stay on this Mac.
    ///
    /// A project name is a client name. `privacy: .public` puts it in the
    /// unified log, which is what a sysdiagnose collects and sends to Apple
    /// or a vendor. Event kinds may be public; anything carrying a name
    /// may not.
    func testNoProjectDetailIsLoggedPublicly() throws {
        for file in try sources() {
            XCTAssertFalse(file.text.contains("detail, privacy: .public"),
                           "\(file.name) logs detail publicly, and detail carries project names.")
        }
    }

    /// Tier 2 answers "what is Resolve showing right now", so a failed read
    /// must be silence, not the last thing we happened to see.
    func testTierTwoAsksForAFreshNameNotACachedOne() throws {
        let switcher = try sources().first { $0.name == "ProjectAutoSwitcher.swift" }
        let text = try XCTUnwrap(switcher?.text)
        XCTAssertTrue(text.contains("detector.freshProjectName()"),
                      "Tier 2 must call freshProjectName()")
        XCTAssertFalse(text.contains("detector.detectProjectName()"),
                       "detectProjectName() returns the last known name on every failure "
                     + "path — as a live observation that re-asserts a stale project.")
    }
}
