import XCTest
@testable import Cutaway

/// Retention rules that exist because of a real loss, pinned so a future
/// tidy-up cannot quietly undo them.
final class RetentionTests: XCTestCase {

    // 9 — the pre-incident copy must outlive every rotation rule.
    func testTheOldestGenerationIsNeverEvicted() {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let now = fmt.date(from: "20260908-120000")!
        // The pre-incident copy: far outside the 30-day daily window and far
        // outside keep-newest-7. Only the eldest rule saves it.
        var names = ["billing-20260601-120000"]
        for day in 0..<20 {
            names.append("billing-" + fmt.string(from: now.addingTimeInterval(-Double(day) * 86_400)))
        }
        let keepers = StoreBackup.survivors(of: names, keep: 7, dailyDays: 30, now: now)
        XCTAssertTrue(keepers.contains("billing-20260601-120000"),
                      "the copy from before the incident dies without this rule")
        XCTAssertEqual(keepers.count, 21, "everything else here is inside the daily window")
    }

    // 10 — replaced stores are not backups and never rotate; without a reaper
    // they accumulate one full store per restore, forever.
    func testReplacedStoresAreReapedButTheNewestSurvives() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("billing.store")
        try Data("live".utf8).write(to: store)

        let old = dir.appendingPathComponent("billing.store.replaced-2026-07-01T10-00-00")
        let newest = dir.appendingPathComponent("billing.store.replaced-2026-09-07T10-00-00")
        for url in [old, newest] { try Data("copy".utf8).write(to: url) }
        let longAgo = Date(timeIntervalSince1970: 1_784_000_000)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)

        let backups = dir.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let staleStaging = backups.appendingPathComponent(".staging-old", isDirectory: true)
        try FileManager.default.createDirectory(at: staleStaging, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: staleStaging.path)

        StoreBackup.reapLitter(storeURL: store, backupsDir: backups, now: Date(timeIntervalSince1970: 1_788_000_000))

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "a 40-day-old copy goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.path), "the newest copy is the only undo there is")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path), "the live store is never litter")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleStaging.path), "an abandoned staging folder goes")
    }
}
