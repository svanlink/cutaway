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

    /// SQLite's own quick_check, read-only. False for a torn or foreign file.
    static func quickCheckOK(_ url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return false }
        return String(cString: c) == "ok"
    }

    /// A restore is staged while the app runs (the live store cannot be
    /// overwritten under an open connection) and applied on the next launch
    /// before anything opens it. The replaced store is kept beside it.
    static func pendingRestoreURL(for target: URL = url()) -> URL {
        URL(fileURLWithPath: target.path + ".restore-pending")
    }

    static func stagePendingRestore(from backupFolder: URL, target: URL = url(),
                                    fm: FileManager = .default) throws {
        let src = backupFolder.appendingPathComponent(target.lastPathComponent)
        guard fm.fileExists(atPath: src.path), holdsCutawayTables(src) else {
            throw NSError(domain: "Cutaway", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "That folder does not hold a Cutaway backup.")])
        }
        let pending = pendingRestoreURL(for: target)
        try? fm.removeItem(at: pending)
        try fm.copyItem(at: src, to: pending)
        // A launch-time backup carries the WAL beside the store; a snapshot
        // has it folded in. Bring the sidecar along when it exists.
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
