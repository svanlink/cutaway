import XCTest
import SQLite3
@testable import Cutaway

/// The eleven cases the 2026-09-07 arbitration named. Ten of them failed
/// before the classifier existed: one Bool could not tell a locked file from
/// a corrupt one, and a zero-byte file — a valid empty database — passed as
/// healthy while good backups sat unused.
final class StoreVerdictTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("verdict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { [dir] in
            if let dir { try? FileManager.default.removeItem(at: dir) }
        }
    }

    /// A store with the tables Cutaway looks for.
    @discardableResult
    private func makeStore(_ name: String, sessions: Int = 0, foreign: Bool = false) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let table = foreign ? "ZAPIREQUESTMODEL" : "ZPROJECT"
        XCTAssertEqual(sqlite3_exec(db, "create table \(table) (Z_PK integer primary key)", nil, nil, nil), SQLITE_OK)
        if !foreign {
            XCTAssertEqual(sqlite3_exec(db, "create table ZWORKSESSION (Z_PK integer primary key)", nil, nil, nil), SQLITE_OK)
            for _ in 0..<sessions {
                XCTAssertEqual(sqlite3_exec(db, "insert into ZWORKSESSION default values", nil, nil, nil), SQLITE_OK)
            }
        }
        return url
    }

    // 1 — the disk saying no is never the file saying no.
    func testAnUnreadableStoreIsNotDamaged() throws {
        let url = try makeStore("billing.store")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        guard case .unreadable = StorePath.verdict(url) else {
            return XCTFail("a permission bit must never propose a restore, got \(StorePath.verdict(url))")
        }
    }

    // 2 — the case that let the incident repeat silently.
    func testAZeroByteStoreIsDamaged() throws {
        let url = dir.appendingPathComponent("billing.store")
        try Data().write(to: url)
        guard case .damaged = StorePath.verdict(url) else {
            return XCTFail("an empty file is a valid database — only the schema tells it apart")
        }
    }

    // 3 — another app's tables in our file: exactly what happened in September.
    func testAForeignSchemaIsDamaged() throws {
        let url = try makeStore("billing.store", foreign: true)
        guard case .damaged = StorePath.verdict(url) else { return XCTFail("foreign schema must be damaged") }
    }

    // 4 — and a legitimately empty first run must NOT be.
    func testAnEmptyCutawayStoreIsUsable() throws {
        let url = try makeStore("billing.store", sessions: 0)
        XCTAssertEqual(StorePath.verdict(url), .usable, "restoring over a fresh install is the incident in reverse")
    }

    func testAMissingStoreIsAbsent() {
        XCTAssertEqual(StorePath.verdict(dir.appendingPathComponent("nothing.store")), .absent)
    }

    // 5, 6 — the owner's backups span three filenames across two renames.
    func testAnyHistoricalBackupNameOpens() throws {
        for name in ["default.store", "timex.store", "billing.store"] {
            let folder = dir.appendingPathComponent("billing-2026\(name.count)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let src = try makeStore("tmp-\(name)", sessions: 3)
            try FileManager.default.moveItem(at: src, to: folder.appendingPathComponent(name))
            XCTAssertNotNil(StorePath.storeFile(in: folder, preferring: "billing.store"),
                            "\(name) must be restorable — ten of twelve real backups were not")
        }
    }

    // 7 — a torn backup is skipped, not offered.
    func testATornBackupIsSkippedForTheNextUsableOne() throws {
        let bad = dir.appendingPathComponent("billing-20260907-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data().write(to: bad.appendingPathComponent("billing.store"))
        let good = dir.appendingPathComponent("billing-20260906-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        let src = try makeStore("tmp.store", sessions: 5)
        try FileManager.default.moveItem(at: src, to: good.appendingPathComponent("default.store"))

        let chosen = StorePath.newestUsableBackup(in: dir, preferring: "billing.store")
        XCTAssertEqual(chosen?.lastPathComponent, good.lastPathComponent, "the newest READABLE one")
    }

    // The count that tells a real backup from a harness one.
    func testTheCandidateCarriesItsSessionCount() throws {
        let folder = dir.appendingPathComponent("billing-20260906-120000", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let src = try makeStore("tmp.store", sessions: 14)
        try FileManager.default.moveItem(at: src, to: folder.appendingPathComponent("default.store"))
        let candidate = StoreBootstrap.newestCandidate(in: dir, preferring: "billing.store")
        XCTAssertEqual(candidate?.sessions, 14)
        XCTAssertEqual(candidate?.storeName, "default.store")
    }

    // 11 — planning is pure: a damaged store asks, and nothing moves.
    func testPlanningADamagedStoreAsksAndMutatesNothing() throws {
        let store = dir.appendingPathComponent("billing.store")
        try Data().write(to: store)
        let backups = dir.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let folder = backups.appendingPathComponent("billing-20260906-120000", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let src = try makeStore("tmp.store", sessions: 7)
        try FileManager.default.moveItem(at: src, to: folder.appendingPathComponent("billing.store"))

        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        guard case .askBeforeRestoring(_, let candidate) = StoreBootstrap.plan(storeURL: store, backupsDir: backups) else {
            return XCTFail("a damaged store must ASK, never act")
        }
        XCTAssertEqual(candidate?.sessions, 7)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), before,
                       "planning must not touch the disk")
        XCTAssertEqual(try Data(contentsOf: store).count, 0, "the damaged file is left exactly as it was")
    }

    func testAUsableStoreJustOpens() throws {
        let store = try makeStore("billing.store", sessions: 2)
        XCTAssertEqual(StoreBootstrap.plan(storeURL: store, backupsDir: dir), .open)
    }
}
