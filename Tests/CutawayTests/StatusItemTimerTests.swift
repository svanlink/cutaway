import XCTest
@testable import Cutaway

/// The status item ran a second 1 Hz timer purely to resize the pill — one
/// that fired while paused, while no project was selected, while the app sat
/// in the background with a static number, on a machine the user is
/// rendering video on. The engine already ticks once a second.
final class StatusItemTimerTests: XCTestCase {

    private var source: String {
        get throws {
            var root = URL(fileURLWithPath: #filePath)
            for _ in 0..<3 { root.deleteLastPathComponent() }
            return try String(contentsOf: root.appendingPathComponent(
                "Sources/Cutaway/UI/StatusItemController.swift"), encoding: .utf8)
        }
    }

    func testTheStatusItemOwnsNoTimer() throws {
        let text = try source
        XCTAssertFalse(text.contains("Timer.scheduledTimer"),
                       "the engine's tick is the app's clock; a second one is drift and battery")
        XCTAssertFalse(text.contains("resizeTimer"), "and its bookkeeping should be gone with it")
    }

    func testItSubscribesToTheEnginesTickInstead() throws {
        XCTAssertTrue(try source.contains("model.onEngineTick"),
                      "width and label still have to keep up — via the existing clock")
    }
}

/// The tick fan-out itself: a second observer must not disturb the first.
@MainActor
final class EngineTickFanoutTests: XCTestCase {

    final class FakeProbes: SystemProbing, @unchecked Sendable {
        var frontmost: String? = DetectionInput.resolveBundleIDs[0]
        var idle: TimeInterval = 0
        func frontmostBundleID() -> String? { frontmost }
        func secondsSinceLastInput() -> TimeInterval { idle }
    }

    func testEveryTickReachesTheObserver() {
        let store = UserDefaults(suiteName: "cutaway.tests.\(UUID().uuidString)")!
        let engine = DetectionEngine(probes: FakeProbes(), defaults: store)
        var ticks = 0
        engine.onTick = { ticks += 1 }
        for _ in 0..<5 { engine.tick() }
        XCTAssertEqual(ticks, 5, "the pill's width and label depend on every one of these")
    }
}
