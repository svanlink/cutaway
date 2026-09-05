import XCTest
@testable import Cutaway

/// A store is a set of files. SQLite runs in WAL mode, so recent writes live
/// in `-wal` while the main `.store` sits byte-identical until a checkpoint.
/// The skip-check compared only the main file, so it could decide "nothing
/// changed" with a session's billing data still in the WAL — most readily
/// right after a crash, which is the launch where the WAL holds the work
/// nothing else has.
final class BackupWALTests: XCTestCase {

    private var dir: URL!
    private var store: URL!
    private var backups: URL!
    private var fm: FileManager { .default }

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wal-backup-tests-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        store = dir.appendingPathComponent("timex.store")
        backups = dir.appendingPathComponent("Backups")
    }

    override func tearDown() { try? fm.removeItem(at: dir) }

    private func date(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + s) }
    private func write(_ text: String, suffix: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: store.path + suffix))
    }

    /// The defect: main file untouched, new work sitting in the WAL.
    func testAChangedWALForcesABackup() throws {
        try write("main", suffix: "")
        try write("wal-v1", suffix: "-wal")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))

        try write("wal-v2", suffix: "-wal")          // an hour of editing, unflushed
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                        "billing data in the WAL is still billing data")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: backups.path).count, 2)
    }

    /// A WAL that has just appeared is the crash case.
    func testAWALAppearingForcesABackup() throws {
        try write("main", suffix: "")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))

        try write("fresh", suffix: "-wal")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                        "a WAL that did not exist at the last backup is a change")
    }

    /// And one that has been checkpointed away, likewise.
    func testAWALDisappearingForcesABackup() throws {
        try write("main", suffix: "")
        try write("wal", suffix: "-wal")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))

        try fm.removeItem(at: URL(fileURLWithPath: store.path + "-wal"))
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                        "the store's shape changed even though the main file did not")
    }

    func testATrulyIdenticalTrioStillSkips() throws {
        try write("main", suffix: "")
        try write("wal", suffix: "-wal")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        XCTAssertNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                     "nothing changed — a second copy would be waste, not safety")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: backups.path).count, 1)
    }

    /// `-shm` is a derived index, rebuilt from the other two. Churn in it is
    /// not new billing data and must not spawn a backup on every launch.
    func testShmChurnAloneDoesNotForceABackup() throws {
        try write("main", suffix: "")
        try write("wal", suffix: "-wal")
        try write("shm-v1", suffix: "-shm")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))

        try write("shm-v2", suffix: "-shm")
        XCTAssertNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                     "a rebuilt index is not a reason to keep another copy")
    }

    func testTheBackupStillContainsEveryFile() throws {
        try write("main", suffix: "")
        try write("wal", suffix: "-wal")
        try write("shm", suffix: "-shm")
        let dest = try XCTUnwrap(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dest.path).sorted(),
                       ["manifest.json", "timex.store", "timex.store-shm", "timex.store-wal"],
                       "deciding on two files must not stop us copying all three")
    }
}
