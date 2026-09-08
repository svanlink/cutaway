import Foundation
import SQLite3

/// Where the billing database lives — and where it must never live.
///
/// SwiftData names an unnamed store `default.store` in Application Support,
/// and so does every other SwiftData app that names nothing. One such app
/// on the owner's Mac opened that file three times in a week and rewrote
/// it to its own schema; Cutaway's tables went with it each time. The
/// backups (which had always copied `default.store`) are what brought the
/// work back. Cutaway's store is named, and inside Cutaway's own folder.
enum StorePath {
    static func url(appSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                    scenarioDataDir: String? = ScenarioMode.dataDir,
                    isTestRun: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) -> URL {
        // Verification runs live in their own quarantined store — the real
        // billing database is untouchable from scenario mode.
        if let scenarioDataDir { return URL(fileURLWithPath: scenarioDataDir).appendingPathComponent("timex.store") }
        // Nor may the unit-test host, which is this app launched by XCTest.
        if isTestRun {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cutaway-tests", isDirectory: true).appendingPathComponent("timex.store")
        }
        return appSupport.appendingPathComponent("Cutaway", isDirectory: true).appendingPathComponent("billing.store")
    }

    /// The path every release before 1.3.2 used.
    static var legacyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("default.store")
    }

    /// One-time: if the named store does not exist yet and the shared file
    /// still holds Cutaway's tables, copy it (store, -wal, -shm) into place.
    /// The shared file is never removed — it is not ours alone. Returns
    /// whether an adoption happened.
    @discardableResult
    static func adoptLegacyIfNeeded(legacy: URL = legacyURL, target: URL = url(),
                                    fm: FileManager = .default) throws -> Bool {
        guard !fm.fileExists(atPath: target.path), fm.fileExists(atPath: legacy.path),
              holdsCutawayTables(legacy) else { return false }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: legacy.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: URL(fileURLWithPath: target.path + suffix))
        }
        return true
    }

    /// What the app thinks of a store file.
    ///
    /// The distinction that matters: `unreadable` is the DISK saying no —
    /// a permission bit, a full volume, a Time Machine lock. Those heal, and
    /// a restore does not give back the minutes it drops. `damaged` is the
    /// FILE saying no. Before 2026-09-08 both collapsed into one Bool, so a
    /// locked file could trigger a restore over good data, while a zero-byte
    /// file — which is a perfectly valid empty database — passed as healthy
    /// and let SwiftData start the owner from nothing.
    enum Verdict: Equatable {
        case absent
        case usable
        case unreadable(String)
        case damaged(String)

        var isUsable: Bool { self == .usable }
    }

    /// `deepCheck` runs SQLite's page scan, which is O(file). Existence, the
    /// open, and the schema probe are O(1) and always run.
    static func verdict(_ url: URL, deepCheck: Bool = true) -> Verdict {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        guard rc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            // NOTADB and CORRUPT are the file. Everything else — and anything
            // unrecognised — is treated as the disk, because the safe way to
            // be wrong is to touch nothing.
            return (rc == SQLITE_NOTADB || rc == SQLITE_CORRUPT)
                ? .damaged("the file is not a database (\(msg))")
                : .unreadable("the store could not be opened (\(msg))")
        }

        if deepCheck {
            var stmt: OpaquePointer?
            // sqlite3_open_v2 does not read the header — a file of garbage
            // opens fine and only fails here, and that failure is the FILE.
            guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else {
                return classify(sqlite3_errcode(db), db: db,
                                damaged: "the store is not a database",
                                unreadable: "the integrity check could not run")
            }
            defer { sqlite3_finalize(stmt) }
            let step = sqlite3_step(stmt)
            if step == SQLITE_BUSY || step == SQLITE_LOCKED || step == SQLITE_IOERR {
                return .unreadable("the store is locked or unreadable right now")
            }
            guard step == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else {
                return classify(step, db: db,
                                damaged: "the integrity check could not read the store",
                                unreadable: "the integrity check stopped early")
            }
            let answer = String(cString: c)
            guard answer == "ok" else { return .damaged("the integrity check said: \(answer)") }
        }

        // A zero-byte file IS a valid empty database — quick_check says "ok".
        // Only the schema tells it apart from a real store.
        switch tableCount(db) {
        case 0: return .damaged("the store holds no tables at all")
        case nil: return .unreadable("the schema could not be read")
        default: break
        }
        guard hasTable(db, "ZPROJECT") else {
            return .damaged("the store holds another app's tables")
        }
        // ZPROJECT with zero rows is a legitimate first run. Restoring over it
        // would be the 2026-08-23 loop in reverse.
        return .usable
    }

    /// NOTADB and CORRUPT are the file itself; anything else is treated as
    /// the disk, because the safe way to be wrong is to touch nothing.
    private static func classify(_ rc: Int32, db: OpaquePointer?,
                                 damaged: String, unreadable: String) -> Verdict {
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
        return (rc == SQLITE_NOTADB || rc == SQLITE_CORRUPT)
            ? .damaged("\(damaged) (\(detail))")
            : .unreadable("\(unreadable) (\(detail))")
    }

    /// How many work sessions a store holds — the number that tells a real
    /// backup from a harness one, so it belongs in front of the owner before
    /// they choose to restore.
    static func sessionCount(_ url: URL) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        guard hasTable(db, "ZWORKSESSION") else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select count(*) from ZWORKSESSION", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : nil
    }

    private static func tableCount(_ db: OpaquePointer?) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select count(*) from sqlite_master where type='table'", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : nil
    }

    private static func hasTable(_ db: OpaquePointer?, _ name: String) -> Bool {
        var stmt: OpaquePointer?
        let sql = "select count(*) from sqlite_master where type='table' and name=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) > 0
    }

    /// The store inside a backup folder, found by CONTENT, not by name.
    ///
    /// The owner's twelve backup folders span three names — `default.store`,
    /// `timex.store`, `billing.store` — because the app was renamed twice.
    /// Matching on the live store's filename made ten of them unopenable,
    /// including every backup that has ever actually recovered lost work.
    static func storeFile(in backupFolder: URL, preferring preferredName: String? = nil,
                          fm: FileManager = .default) -> URL? {
        let entries = (try? fm.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: nil)) ?? []
        let candidates = entries
            .filter { $0.pathExtension == "store" }
            .filter { verdict($0).isUsable }
        if let preferredName, let exact = candidates.first(where: { $0.lastPathComponent == preferredName }) {
            return exact
        }
        // Several usable stores in one folder is not a shape the app creates;
        // if it happens, the biggest one holds the most work.
        return candidates.max { size(of: $0) < size(of: $1) }
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// Newest-first, skipping folders whose store is torn, foreign or empty.
    static func newestUsableBackup(in backupsDir: URL, preferring preferredName: String? = nil,
                                   fm: FileManager = .default) -> URL? {
        let folders = ((try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("billing-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        return folders.first { storeFile(in: $0, preferring: preferredName, fm: fm) != nil }
    }

    /// A restore is staged while the app runs (the live store cannot be
    /// overwritten under an open connection) and applied on the next launch
    /// before anything opens it. The replaced store is kept beside it.
    static func pendingRestoreURL(for target: URL = url()) -> URL {
        URL(fileURLWithPath: target.path + ".restore-pending")
    }

    static func stagePendingRestore(from backupFolder: URL, target: URL = url(),
                                    fm: FileManager = .default) throws {
        guard let src = storeFile(in: backupFolder, preferring: target.lastPathComponent, fm: fm) else {
            throw NSError(domain: "Cutaway", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "That folder does not hold a readable Cutaway backup.")])
        }
        let pending = pendingRestoreURL(for: target)
        try? fm.removeItem(at: pending)
        try fm.copyItem(at: src, to: pending)
        // The backup's store may be called something else entirely — the
        // sidecars follow ITS stem, and land under the LIVE name.
        for suffix in ["-wal", "-shm"] {
            let s = URL(fileURLWithPath: src.path + suffix)
            try? fm.removeItem(at: URL(fileURLWithPath: pending.path + suffix))
            if fm.fileExists(atPath: s.path) { try fm.copyItem(at: s, to: URL(fileURLWithPath: pending.path + suffix)) }
        }
    }

    /// Returns whether a restore was applied.
    @discardableResult
    static func applyPendingRestore(target: URL = url(), now: Date = Date(),
                                    fm: FileManager = .default) throws -> Bool {
        let pending = pendingRestoreURL(for: target)
        guard fm.fileExists(atPath: pending.path) else { return false }
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let live = URL(fileURLWithPath: target.path + suffix)
            if fm.fileExists(atPath: live.path) {
                try fm.moveItem(at: live, to: URL(fileURLWithPath: target.path + ".replaced-\(stamp)" + suffix))
            }
        }
        for suffix in ["", "-wal", "-shm"] {
            let p = URL(fileURLWithPath: pending.path + suffix)
            if fm.fileExists(atPath: p.path) { try fm.moveItem(at: p, to: URL(fileURLWithPath: target.path + suffix)) }
        }
        return true
    }

    /// Read-only look at the schema: is there a ZPROJECT table?
    static func holdsCutawayTables(_ url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select count(*) from sqlite_master where type='table' and name='ZPROJECT'", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) > 0
    }
}
