import XCTest
@testable import Cutaway

final class DetectionStateTests: XCTestCase {

    private func input(
        frontmost: String? = DetectionInput.resolveBundleIDs.first,
        secondsSinceInput: TimeInterval = 0,
        idleThreshold: TimeInterval = 120,
        manuallyPaused: Bool = false,
        isAsleep: Bool = false,
        hasActiveProject: Bool = true
    ) -> DetectionInput {
        DetectionInput(
            frontmostBundleID: frontmost,
            secondsSinceInput: secondsSinceInput,
            idleThreshold: idleThreshold,
            manuallyPaused: manuallyPaused,
            isAsleep: isAsleep,
            hasActiveProject: hasActiveProject
        )
    }

    // MARK: - Recording

    func testRecordsWhenResolveFrontmostAndInputFresh() {
        XCTAssertEqual(DetectionState.evaluate(input()), .recording)
    }

    func testRecordsJustBelowIdleThreshold() {
        XCTAssertEqual(DetectionState.evaluate(input(secondsSinceInput: 119.9)), .recording)
    }

    // MARK: - Pause reasons

    func testPausesWhenResolveNotFrontmost() {
        XCTAssertEqual(
            DetectionState.evaluate(input(frontmost: "com.apple.finder")),
            .paused(.notFrontmost)
        )
    }

    func testPausesWhenNoFrontmostApp() {
        XCTAssertEqual(
            DetectionState.evaluate(input(frontmost: nil)),
            .paused(.notFrontmost)
        )
    }

    func testPausesAtIdleThresholdBoundary() {
        XCTAssertEqual(
            DetectionState.evaluate(input(secondsSinceInput: 120)),
            .paused(.inputIdle)
        )
    }

    func testPausesWithCustomIdleThreshold() {
        XCTAssertEqual(
            DetectionState.evaluate(input(secondsSinceInput: 31, idleThreshold: 30)),
            .paused(.inputIdle)
        )
        XCTAssertEqual(
            DetectionState.evaluate(input(secondsSinceInput: 29, idleThreshold: 30)),
            .recording
        )
    }

    func testPausesWhenManuallyPaused() {
        XCTAssertEqual(
            DetectionState.evaluate(input(manuallyPaused: true)),
            .paused(.manual)
        )
    }

    func testPausesDuringSystemSleep() {
        XCTAssertEqual(
            DetectionState.evaluate(input(isAsleep: true)),
            .paused(.systemSleep)
        )
    }

    func testPausesWithoutActiveProject() {
        XCTAssertEqual(
            DetectionState.evaluate(input(hasActiveProject: false)),
            .paused(.noProject)
        )
    }

    // MARK: - Priority ordering: manual > sleep > noProject > notFrontmost > idle

    func testManualPauseWinsOverEverything() {
        XCTAssertEqual(
            DetectionState.evaluate(input(
                frontmost: "com.apple.finder", secondsSinceInput: 999,
                manuallyPaused: true, isAsleep: true, hasActiveProject: false
            )),
            .paused(.manual)
        )
    }

    func testSleepWinsOverProjectAndFrontmost() {
        XCTAssertEqual(
            DetectionState.evaluate(input(
                frontmost: "com.apple.finder", isAsleep: true, hasActiveProject: false
            )),
            .paused(.systemSleep)
        )
    }

    func testNoProjectWinsOverFrontmost() {
        XCTAssertEqual(
            DetectionState.evaluate(input(frontmost: "com.apple.finder", hasActiveProject: false)),
            .paused(.noProject)
        )
    }

    // MARK: - Resolve bundle id variants

    func testRecognizesAllResolveBundleIDs() {
        for id in DetectionInput.resolveBundleIDs {
            XCTAssertEqual(DetectionState.evaluate(input(frontmost: id)), .recording, id)
        }
    }

    // MARK: - Workflow apps (allowlist)

    private func workInput(frontmost: String) -> DetectionInput {
        var i = input(frontmost: frontmost)
        i.workAppPrefixes = DetectionInput.defaultWorkAppPrefixes
        return i
    }

    func testWorkAppRecords() {
        XCTAssertEqual(DetectionState.evaluate(workInput(frontmost: "com.adobe.AfterEffects")), .recording)
    }

    func testWorkAppPrefixMatchesYearedBundleIDs() {
        XCTAssertEqual(DetectionState.evaluate(workInput(frontmost: "com.adobe.PremierePro.2025")), .recording)
    }

    func testNonWorkAppStillPauses() {
        XCTAssertEqual(DetectionState.evaluate(workInput(frontmost: "com.google.Chrome")),
                       .paused(.notFrontmost))
    }

    func testWorkAppStillRespectsIdleThreshold() {
        var i = workInput(frontmost: "com.adobe.Photoshop")
        i.secondsSinceInput = 500
        XCTAssertEqual(DetectionState.evaluate(i), .paused(.inputIdle))
    }
}

final class BridgeCreditTests: XCTestCase {

    func testCreditAddsToOpenSession() {
        var acc = SessionAccumulator()
        acc.tick(state: .recording, interval: 1)
        acc.credit(90)
        XCTAssertEqual(acc.activeSeconds, 91)
    }

    func testCreditIgnoredWithoutOpenSession() {
        var acc = SessionAccumulator()
        acc.credit(90)
        XCTAssertEqual(acc.activeSeconds, 0)
    }

    func testCreditIgnoresNegative() {
        var acc = SessionAccumulator()
        acc.tick(state: .recording, interval: 1)
        acc.credit(-5)
        XCTAssertEqual(acc.activeSeconds, 1)
    }
}

final class SessionAccumulatorTests: XCTestCase {

    func testAccumulatesOnlyWhileRecording() {
        var acc = SessionAccumulator()
        acc.tick(state: .recording, interval: 1)
        acc.tick(state: .recording, interval: 1)
        acc.tick(state: .paused(.inputIdle), interval: 1)
        acc.tick(state: .recording, interval: 1)
        XCTAssertEqual(acc.activeSeconds, 3)
    }

    func testStartsSessionOnFirstRecordingTick() {
        var acc = SessionAccumulator()
        XCTAssertNil(acc.sessionStart)
        acc.tick(state: .recording, interval: 1, now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(acc.sessionStart, Date(timeIntervalSince1970: 1000))
    }

    func testEndSessionReturnsRecordAndResets() {
        var acc = SessionAccumulator()
        let t0 = Date(timeIntervalSince1970: 1000)
        acc.tick(state: .recording, interval: 1, now: t0)
        acc.tick(state: .recording, interval: 1, now: t0.addingTimeInterval(1))
        let record = acc.endSession(at: t0.addingTimeInterval(2))
        XCTAssertEqual(record?.start, t0)
        XCTAssertEqual(record?.end, t0.addingTimeInterval(2))
        XCTAssertEqual(record?.activeSeconds, 2)
        XCTAssertNil(acc.sessionStart)
        XCTAssertEqual(acc.activeSeconds, 0)
    }

    func testEndSessionWithoutStartReturnsNil() {
        var acc = SessionAccumulator()
        XCTAssertNil(acc.endSession(at: Date()))
    }
}

final class PrefsMigrationTests: XCTestCase {
    func testMigratesOnlyMissingKeys() {
        let suite = UserDefaults(suiteName: "cutaway.migration.test")!
        suite.removePersistentDomain(forName: "cutaway.migration.test")
        suite.set("keepme", forKey: "existing")
        PrefsMigration.migrate(from: ["existing": "overwrite", "fresh": 42.0], into: suite)
        XCTAssertEqual(suite.string(forKey: "existing"), "keepme", "existing keys are never overwritten")
        XCTAssertEqual(suite.double(forKey: "fresh"), 42.0, "missing keys migrate")
        suite.removePersistentDomain(forName: "cutaway.migration.test")
    }

    func testNilDomainIsNoop() {
        let suite = UserDefaults(suiteName: "cutaway.migration.test2")!
        suite.removePersistentDomain(forName: "cutaway.migration.test2")
        PrefsMigration.migrate(from: nil, into: suite)
        XCTAssertNil(suite.object(forKey: "anything"))
    }
}
