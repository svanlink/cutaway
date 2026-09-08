import XCTest
import SQLite3
@testable import Cutaway

/// The running app backs itself up: daily, at quit, by hand — a consistent
/// SQLite snapshot of the OPEN store, because the launch backup alone left
/// weeks of work uncovered.
@MainActor
final class BackupScheduleTests: XCTestCase {
    private var dir: URL!
    override func setUp() async throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    /// Written against the interval rather than a hard-coded 24 h: the
    /// number moved from daily to hourly when it turned out a daily tick
    /// left up to 22 hours of billable work unbacked, and a test that pins
    /// the constant only proves the constant has not moved.
    func testDueImmediatelyWhenNeverAndOncePerIntervalAfter() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let interval = BackupPolicy.interval
        XCTAssertTrue(BackupPolicy.isDue(last: nil, now: t0), "a Mac with no backup yet is due now")
        XCTAssertFalse(BackupPolicy.isDue(last: t0, now: t0.addingTimeInterval(interval - 1)))
        XCTAssertTrue(BackupPolicy.isDue(last: t0, now: t0.addingTimeInterval(interval)))
    }

    /// The exposure window is a policy decision, not an accident. An app that
    /// runs for weeks must not leave a working day between generations.
    func testTheExposureWindowIsAtMostAnHour() {
        XCTAssertLessThanOrEqual(BackupPolicy.interval, 3600,
                                 "more than an hour of unbacked work is a day's billing at risk")
    }

    private func count(_ url: URL, _ table: String) -> Int {
        var db: OpaquePointer?; var stmt: OpaquePointer?
        sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil); defer { sqlite3_close(db) }
        sqlite3_prepare_v2(db, "select count(*) from \(table)", -1, &stmt, nil); defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : -1
    }

    func testASnapshotOfAnOpenStoreHoldsTheWorkAndSkipsWhenUnchanged() throws {
        let live = dir.appendingPathComponent("billing.store")
        let backups = dir.appendingPathComponent("Backups")
        let store = try SessionStore(url: live)
        let p = try store.createProject(name: "Nyx", client: "", mode: .hourly, hourlyRate: 85, currency: .chf)
        try store.record(SessionRecord(start: Date(timeIntervalSince1970: 1_800_000_000),
                                       end: Date(timeIntervalSince1970: 1_800_003_600), activeSeconds: 3600), to: p)
        let first = try XCTUnwrap(try StoreBackup.snapshot(storeURL: live, backupsDir: backups, now: Date(timeIntervalSince1970: 1_800_010_000)))
        let copy = first.appendingPathComponent("billing.store")
        XCTAssertEqual(count(copy, "ZPROJECT"), 1)
        XCTAssertEqual(count(copy, "ZWORKSESSION"), 1, "the WAL is folded into the snapshot")
        XCTAssertEqual(StorePath.verdict(copy), .usable)
        XCTAssertNil(try StoreBackup.snapshot(storeURL: live, backupsDir: backups, now: Date(timeIntervalSince1970: 1_800_020_000)),
                     "nothing changed — no second copy")
        XCTAssertEqual(StoreBackup.newest(in: backups)?.lastPathComponent, first.lastPathComponent)
    }
}
