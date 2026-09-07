import XCTest
import SQLite3
@testable import Cutaway

/// The billing store lives in Cutaway's OWN folder. `default.store` in
/// Application Support is the name every SwiftData app gets when it names
/// nothing — another app rewrote it to its schema three times in a week,
/// and Cutaway's tables went with it.
final class StorePathTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("storepath-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    func testTheRealStoreIsNamedAndInsideCutawaysFolder() {
        let u = StorePath.url(appSupport: dir, scenarioDataDir: nil, isTestRun: false)
        XCTAssertEqual(u.path, dir.appendingPathComponent("Cutaway/billing.store").path)
        XCTAssertNotEqual(u.lastPathComponent, "default.store")
    }

    func testScenarioAndTestRunsNeverTouchIt() {
        XCTAssertEqual(StorePath.url(appSupport: dir, scenarioDataDir: "/tmp/s", isTestRun: false).path, "/tmp/s/timex.store")
        let t = StorePath.url(appSupport: dir, scenarioDataDir: nil, isTestRun: true)
        XCTAssertFalse(t.path.hasPrefix(dir.path), "a test host must not open the user's store")
    }

    private func makeStore(at url: URL, table: String) {
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, "create table \(table) (Z_PK integer primary key); insert into \(table) values (1);", nil, nil, nil)
        sqlite3_close(db)
    }

    func testLegacyDataIsAdoptedOnceAndNeverDeleted() throws {
        let legacy = dir.appendingPathComponent("default.store")
        let target = dir.appendingPathComponent("Cutaway/billing.store")
        makeStore(at: legacy, table: "ZPROJECT")
        XCTAssertTrue(try StorePath.adoptLegacyIfNeeded(legacy: legacy, target: target))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "the other app's file is not ours to remove")
        XCTAssertFalse(try StorePath.adoptLegacyIfNeeded(legacy: legacy, target: target), "adopt once")
    }

    func testAForeignDefaultStoreIsNotAdopted() throws {
        let legacy = dir.appendingPathComponent("default.store")
        let target = dir.appendingPathComponent("Cutaway/billing.store")
        makeStore(at: legacy, table: "ZAPIREQUESTMODEL")
        XCTAssertFalse(try StorePath.adoptLegacyIfNeeded(legacy: legacy, target: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testQuickCheckRejectsGarbage() throws {
        let junk = dir.appendingPathComponent("junk.store")
        try Data(repeating: 0x41, count: 4096).write(to: junk)
        XCTAssertFalse(StorePath.quickCheckOK(junk))
        let good = dir.appendingPathComponent("good.store")
        makeStore(at: good, table: "ZPROJECT")
        XCTAssertTrue(StorePath.quickCheckOK(good))
    }

    func testAPendingRestoreIsAppliedOnceAndKeepsTheReplacedStore() throws {
        let target = dir.appendingPathComponent("Cutaway/billing.store")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        makeStore(at: target, table: "ZPROJECT")                       // the live one
        let backup = dir.appendingPathComponent("Backups/billing-20260906-120000")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        makeStore(at: backup.appendingPathComponent("billing.store"), table: "ZPROJECT")
        try StorePath.stagePendingRestore(from: backup, target: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: StorePath.pendingRestoreURL(for: target).path))
        XCTAssertTrue(try StorePath.applyPendingRestore(target: target, now: Date(timeIntervalSince1970: 0)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: StorePath.pendingRestoreURL(for: target).path))
        let kept = try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)
        XCTAssertTrue(kept.contains { $0.hasPrefix("billing.store.replaced-") }, "the replaced store is kept: \(kept)")
        XCTAssertFalse(try StorePath.applyPendingRestore(target: target), "applied once")
    }

    func testAForeignFolderCannotBeStagedAsARestore() throws {
        let target = dir.appendingPathComponent("Cutaway/billing.store")
        let backup = dir.appendingPathComponent("Backups/billing-20260906-120000")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        makeStore(at: backup.appendingPathComponent("billing.store"), table: "ZAPIREQUESTMODEL")
        XCTAssertThrowsError(try StorePath.stagePendingRestore(from: backup, target: target))
    }
}
