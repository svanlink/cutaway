import XCTest
@testable import Cutaway

/// Rotation hardening, born of a real incident: the store was wiped
/// externally, same-day launches filled keep-newest-7 with generations of
/// the wreckage, and the only backups still holding the user's real project
/// were a few launches from eviction. Recency alone must never evict
/// history.
final class BackupRotationTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    private func name(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> String {
        String(format: "billing-%04d%02d%02d-%02d%02d00", y, mo, d, h, mi)
    }

    // MARK: - The pure retention rule

    /// The incident, replayed on names: three old good generations, then a
    /// burst of ten same-day generations after the wipe. Yesterday's newest
    /// must survive the entire burst.
    func testSameDaySpamCannotEvictAnotherDaysNewest() {
        // The 19th is here only to hold the never-evict-the-eldest pin, so
        // this test still measures the daily rule and not that one.
        var names = [name(2026, 8, 19, 12),
                     name(2026, 8, 20, 18), name(2026, 8, 20, 23, 26), name(2026, 8, 20, 23, 36)]
        names += (0..<10).map { name(2026, 8, 23, 11, $0) }

        let keepers = StoreBackup.survivors(of: names, keep: 7, dailyDays: 30,
                                            now: date(2026, 8, 23))
        XCTAssertTrue(keepers.contains(name(2026, 8, 20, 23, 36)),
                      "the pre-wipe day's newest generation must survive the burst")
        XCTAssertFalse(keepers.contains(name(2026, 8, 20, 18)),
                       "but only its newest — dailies are one per day")
    }

    func testOnlyTheNewestOfEachDayIsRetainedAsADaily() {
        let names = [name(2026, 8, 10, 9), name(2026, 8, 10, 17),
                     name(2026, 8, 15, 9), name(2026, 8, 15, 17)]
        let keepers = StoreBackup.survivors(of: names, keep: 2, dailyDays: 30,
                                            now: date(2026, 8, 23))
        XCTAssertEqual(keepers, [name(2026, 8, 10, 9), name(2026, 8, 10, 17),
                                 name(2026, 8, 15, 9), name(2026, 8, 15, 17)],
                       "10th keeps its 17:00 as the daily and its 09:00 as the eldest; keep-2 covers the 15th")
    }

    func testDailiesExpireButTheNewestGenerationsNeverDo() {
        // Nothing for two months: every generation is far older than the
        // daily window, and every one must still survive via keep-newest.
        let names = (1...5).map { name(2026, 5, $0, 12) }
        let keepers = StoreBackup.survivors(of: names, keep: 7, dailyDays: 30,
                                            now: date(2026, 8, 23))
        XCTAssertEqual(keepers.count, 5,
                       "an unused app must not rot its own last backups away")
    }

    func testAnOldDailyOutsideTheWindowIsReleased() {
        var names = [name(2026, 5, 1, 12)]                      // eldest — pinned forever
        names += [name(2026, 6, 1, 12)]                         // 83 days old
        names += (0..<8).map { name(2026, 8, 23, 10, $0) }      // 8 fresh ones
        let keepers = StoreBackup.survivors(of: names, keep: 7, dailyDays: 30,
                                            now: date(2026, 8, 23))
        XCTAssertFalse(keepers.contains(name(2026, 6, 1, 12)),
                       "beyond the window and displaced from keep-newest, it may go")
        XCTAssertTrue(keepers.contains(name(2026, 5, 1, 12)),
                      "except the eldest, which is the copy from before whatever went wrong")
        XCTAssertEqual(keepers.count, 8)
    }

    func testAnUnparsableNameIsNeverDeleted() {
        let names = ["billing-garbage", name(2026, 8, 23, 10), name(2026, 8, 23, 11)]
        let keepers = StoreBackup.survivors(of: names, keep: 1, dailyDays: 30,
                                            now: date(2026, 8, 23))
        XCTAssertTrue(keepers.contains("billing-garbage"),
                      "destroying what cannot be classified is how a bug eats a backup")
    }

    // MARK: - The VERIFY line, end to end on real files

    /// A store wiped and reseeded N times still retains a backup of the
    /// pre-wipe state after N rotations.
    func testThePreWipeBackupSurvivesTenPostWipeRotations() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rotation-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let store = dir.appendingPathComponent("timex.store")
        let backups = dir.appendingPathComponent("Backups")

        // Day 1: real billing data, backed up.
        try Data("REAL-BILLING-DATA".utf8).write(to: store)
        let goodDay = date(2026, 8, 20, 23)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: goodDay))

        // Day 4: the store is wiped and rewritten, ten launches in a row.
        for i in 0..<10 {
            try Data("wreckage-\(i)".utf8).write(to: store)
            _ = try StoreBackup.backUp(storeURL: store, backupsDir: backups,
                                       now: date(2026, 8, 23, 10).addingTimeInterval(Double(i) * 60))
        }

        let surviving = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("billing-") }
        let preWipe = surviving.first { $0.lastPathComponent.hasPrefix("billing-20260820") }
        let recovered = try XCTUnwrap(preWipe, "the pre-wipe generation was rotated away")
        XCTAssertEqual(try Data(contentsOf: recovered.appendingPathComponent("timex.store")),
                       Data("REAL-BILLING-DATA".utf8),
                       "surviving is not enough — it must still hold the real data")
    }
}
