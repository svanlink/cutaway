import XCTest
@testable import Cutaway

/// A crash snapshot names the project it belongs to, so recovery cannot
/// land a phantom session on whatever happens to be selected weeks later.
@MainActor
final class CrashSnapshotTests: XCTestCase {
    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    /// The snapshot is the retry: it survives a close whose save failed.
    func testAFailedSaveAtCloseKeepsTheSnapshot() {
        let store = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        let engine = DetectionEngine(probes: FakeProbes(), defaults: store)
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { clock }
        engine.onSessionClosed = { _ in false }         // the store threw
        for _ in 0..<20 { clock = clock.addingTimeInterval(1); engine.tick() }
        engine.stop()
        XCTAssertNotNil(DetectionEngine.peekCrashedSession(in: store), "a failed save must be retried next launch")
    }

    func testTheSnapshotCarriesTheProjectAndClearingRemovesIt() {
        let store = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        let engine = DetectionEngine(probes: FakeProbes(), defaults: store)
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        engine.now = { clock }
        engine.projectNameForSnapshot = { "Nyx Fashion Film" }

        for _ in 0..<20 { clock = clock.addingTimeInterval(1); engine.tick() }

        let peeked = DetectionEngine.peekCrashedSession(in: store)
        XCTAssertEqual(peeked?.project, "Nyx Fashion Film")
        // Snapshots are written at the 15 s checkpoint, not every tick.
        XCTAssertGreaterThanOrEqual(peeked?.record.activeSeconds ?? 0, 15)

        DetectionEngine.clearCrashedSessionSnapshot(in: store)
        XCTAssertNil(DetectionEngine.peekCrashedSession(in: store))
        XCTAssertNil(store.string(forKey: "openSession.project"))
    }
}
