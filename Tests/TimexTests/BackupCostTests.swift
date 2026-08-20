import XCTest
@testable import Cutaway

/// Deciding whether to back up used to cost two full reads of the store, on
/// the launch path, before the UI existed. Fine at 80 KB — the size on the
/// development machine — and pointless at 80 MB, which is the size this app
/// is designed to grow toward.
final class BackupCostTests: XCTestCase {

    private var dir: URL!
    private var store: URL!
    private var backups: URL!
    private var fm: FileManager { .default }

    override func setUp() {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("backup-cost-tests-\(UUID().uuidString)")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        store = dir.appendingPathComponent("timex.store")
        backups = dir.appendingPathComponent("Backups")
        StoreBackup.resetDiagnostics()
    }

    override func tearDown() { try? fm.removeItem(at: dir) }

    private func date(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + s) }
    private func write(_ bytes: Int, byte: UInt8 = 0x41, suffix: String = "") throws {
        try Data(repeating: byte, count: bytes).write(to: URL(fileURLWithPath: store.path + suffix))
    }

    func testAnUnchangedStoreIsSkippedWithoutReadingIt() throws {
        try write(2_000_000)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        StoreBackup.resetDiagnostics()

        XCTAssertNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                     "nothing changed")
        XCTAssertEqual(StoreBackup.contentComparisons, 0,
                       "the launch path must not read a two-megabyte database to learn nothing")
    }

    func testAChangedStoreStillBacksUp() throws {
        try write(1000)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        try write(2000)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                        "a bigger store is obviously a changed one")
    }

    /// Size alone is not enough — an edit that replaces bytes in place keeps
    /// the size and must still be caught.
    func testSameSizeDifferentContentIsStillCaught() throws {
        try write(1000, byte: 0x41)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        try write(1000, byte: 0x42)
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                        "same size, different bytes, newer mtime — a change")
    }

    func testAChangedWALIsStillCaughtCheaply() throws {
        try write(1000)
        try write(500, suffix: "-wal")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        StoreBackup.resetDiagnostics()

        try write(600, suffix: "-wal")
        XCTAssertNotNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                        "WAL awareness must survive the optimisation")
        XCTAssertEqual(StoreBackup.contentComparisons, 0, "and it must stay cheap")
    }

    /// Backups taken before manifests existed must not force a copy on every
    /// launch forever — they fall back to the old comparison.
    func testALegacyBackupWithoutAManifestStillDecidesCorrectly() throws {
        try write(1000)
        let dest = try XCTUnwrap(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        try fm.removeItem(at: dest.appendingPathComponent("manifest.json"))
        StoreBackup.resetDiagnostics()

        XCTAssertNil(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(60)),
                     "an unchanged store is still recognised without a manifest")
        XCTAssertEqual(StoreBackup.contentComparisons, 1,
                       "the fallback ran — that is what makes old backups keep working")
    }

    func testTheManifestIsWrittenAlongsideTheCopy() throws {
        try write(1000)
        try write(50, suffix: "-wal")
        let dest = try XCTUnwrap(try StoreBackup.backUp(storeURL: store, backupsDir: backups, now: date(0)))
        let data = try Data(contentsOf: dest.appendingPathComponent("manifest.json"))
        let facts = try JSONDecoder().decode([String: StoreBackup.FileFacts].self, from: data)
        XCTAssertEqual(Set(facts.keys), ["timex.store", "timex.store-wal"],
                       "the manifest records the data files, and only those")
        XCTAssertEqual(facts["timex.store"]?.size, 1000)
    }
}
