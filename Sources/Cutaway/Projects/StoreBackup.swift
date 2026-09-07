import Foundation
import SQLite3
import Darwin

/// Launch-time billing-data backup: copies the SwiftData store trio
/// (.store, -wal, -shm) into a stamped folder under Backups/, skips when
/// nothing changed, and keeps only the newest `keep` backups.
/// Runs BEFORE the container opens, so the files are quiescent.
enum StoreBackup {
    static let defaultKeep = 7
    /// Alongside the newest `keep`, the newest generation of each calendar
    /// day survives this long. Born of the 2026-08-23 incident: the store
    /// was wiped externally, and a burst of same-day launches filled
    /// keep-newest-7 with generations of the EMPTY store — the only backups
    /// still holding the user's real project were the oldest three, a few
    /// launches from eviction. Recency alone must never be able to evict
    /// history; a wipe today cannot touch yesterday's daily for a month, no
    /// matter how many launches spam the rotation.
    static let defaultDailyRetentionDays = 30

    /// Returns the created backup directory, or nil when skipped.
    @discardableResult
    static func backUp(storeURL: URL, backupsDir: URL, now: Date = Date(),
                       keep: Int = defaultKeep,
                       dailyDays: Int = defaultDailyRetentionDays) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }
        try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        // Skip when unchanged — but a store is a SET of files. SQLite runs in
        // WAL mode, so recent writes live in `-wal` while the main file sits
        // byte-identical for as long as it takes to checkpoint. Comparing only
        // `.store` is how a backup gets skipped with a session's billing data
        // still in the WAL, and it says so most readily right after a crash,
        // which is the launch where the WAL holds the unflushed work.
        if let newest = existingBackups(in: backupsDir).last,
           isUnchanged(storeURL: storeURL, since: newest) {
            return nil
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dest = backupsDir.appendingPathComponent("billing-\(fmt.string(from: now))")
        // Copy into a staging folder and rename at the end: a folder carrying
        // the real `billing-…` name is complete by construction. A copy that
        // died mid-WAL used to leave a folder that looked exactly like a good
        // backup — the one the recovery procedure says to restore.
        let staging = backupsDir.appendingPathComponent(".staging-\(fmt.string(from: now))")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for suffix in copiedSuffixes {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                try fm.copyItem(at: src, to: staging.appendingPathComponent(src.lastPathComponent))
            }
            // Record what the store looked like, so the NEXT launch can decide
            // with stat calls instead of reading the whole database.
            writeManifest(facts(for: storeURL), to: staging)
            try fm.moveItem(at: staging, to: dest)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        rotate(backupsDir: backupsDir, keep: keep, dailyDays: dailyDays, now: now)
        return dest
    }

    /// A backup of a store that is OPEN — the app runs for weeks, and the
    /// launch backup alone left the newest work uncovered. SQLite's online
    /// backup API produces a consistent single-file snapshot (WAL folded
    /// in) without touching the live connection. Same skip, same rotation.
    @discardableResult
    static func snapshot(storeURL: URL, backupsDir: URL, now: Date = Date(),
                         keep: Int = defaultKeep,
                         dailyDays: Int = defaultDailyRetentionDays) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }
        try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        if let newest = existingBackups(in: backupsDir).last,
           isUnchanged(storeURL: storeURL, since: newest) {
            return nil
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dest = backupsDir.appendingPathComponent("billing-\(fmt.string(from: now))")
        let staging = backupsDir.appendingPathComponent(".staging-\(fmt.string(from: now))")
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try sqliteCopy(from: storeURL, to: staging.appendingPathComponent(storeURL.lastPathComponent))
            writeManifest(facts(for: storeURL), to: staging)
            try fm.moveItem(at: staging, to: dest)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        rotate(backupsDir: backupsDir, keep: keep, dailyDays: dailyDays, now: now)
        return dest
    }

    struct SnapshotError: Error, CustomStringConvertible { let description: String }

    private static func sqliteCopy(from src: URL, to dst: URL) throws {
        // VACUUM INTO reads the logical database — WAL frames included — and
        // writes one consistent file. (The online-backup API copied the main
        // file's pages without the WAL from a second connection here.)
        var source: OpaquePointer?
        guard sqlite3_open_v2(src.path, &source, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw SnapshotError(description: "open source: \(String(cString: sqlite3_errmsg(source)))")
        }
        defer { sqlite3_close(source) }
        let escaped = dst.path.replacingOccurrences(of: "'", with: "''")
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(source, "VACUUM INTO '\(escaped)'", nil, nil, &err) == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SnapshotError(description: "vacuum into: \(msg)")
        }
    }

    /// Rotate. Two buckets survive: the newest `keep` generations, and
    /// each calendar day's newest generation for `dailyDays` days.
    private static func rotate(backupsDir: URL, keep: Int, dailyDays: Int, now: Date) {
        let fm = FileManager.default
        let all = existingBackups(in: backupsDir)
        let keepers = survivors(of: all.map(\.lastPathComponent),
                                keep: keep, dailyDays: dailyDays, now: now)
        for candidate in all where !keepers.contains(candidate.lastPathComponent) {
            try? fm.removeItem(at: candidate)
        }
    }

    /// The newest complete backup folder, if any.
    static func newest(in backupsDir: URL) -> URL? { existingBackups(in: backupsDir).last }

    /// `-shm` is a derived index, rebuilt from the other two — copied for
    /// completeness, never consulted when deciding whether anything changed.
    private static let dataSuffixes = ["", "-wal"]
    private static let copiedSuffixes = ["", "-wal", "-shm"]

    /// Facts about one file, cheap enough to take on every launch.
    /// Nanosecond mtime, read through `stat` rather than Foundation's `Date`,
    /// which loses that precision at current timestamps.
    struct FileFacts: Codable, Equatable {
        var size: Int
        var mtimeSeconds: Int
        var mtimeNanoseconds: Int
    }

    /// Diagnostics: counts the times the decision fell back to reading the
    /// store's contents, so a test can prove the launch path does not.
    /// `nonisolated(unsafe)` for the compiler, not as a real hazard — backup
    /// runs once, from one place, before the container opens.
    nonisolated(unsafe) private(set) static var contentComparisons = 0

    static func resetDiagnostics() { contentComparisons = 0 }

    private static func facts(for storeURL: URL) -> [String: FileFacts] {
        var result: [String: FileFacts] = [:]
        for suffix in dataSuffixes {
            let path = storeURL.path + suffix
            var st = stat()
            guard stat(path, &st) == 0 else { continue }
            result[URL(fileURLWithPath: path).lastPathComponent] = FileFacts(
                size: Int(st.st_size),
                mtimeSeconds: Int(st.st_mtimespec.tv_sec),
                mtimeNanoseconds: Int(st.st_mtimespec.tv_nsec)
            )
        }
        return result
    }

    private static func manifestURL(in backup: URL) -> URL {
        backup.appendingPathComponent("manifest.json")
    }

    private static func writeManifest(_ facts: [String: FileFacts], to backup: URL) {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: manifestURL(in: backup))
    }

    /// Cheap first, content only as a fallback. Deciding used to cost two
    /// full reads of the store on the launch path, before the UI existed —
    /// fine at 80 KB, pointless at 80 MB, and it grows with exactly the
    /// history the app is designed to accumulate.
    private static func isUnchanged(storeURL: URL, since backup: URL) -> Bool {
        if let data = try? Data(contentsOf: manifestURL(in: backup)),
           let recorded = try? JSONDecoder().decode([String: FileFacts].self, from: data) {
            // A file cannot change without its size or mtime moving, so equal
            // facts mean equal contents. Unequal facts may be a false alarm,
            // and a spare backup is the safe direction to be wrong in.
            return recorded == facts(for: storeURL)
        }
        // Backups taken before manifests existed: fall back to the old
        // comparison rather than forcing a copy on every launch forever.
        contentComparisons += 1
        return matchesBackup(storeURL: storeURL, backup: backup)
    }

    /// True only when every DATA file matches the backup's copy. A file
    /// present on one side and absent on the other counts as a difference —
    /// a WAL that has just appeared is exactly the case this must catch.
    private static func matchesBackup(storeURL: URL, backup: URL) -> Bool {
        for suffix in dataSuffixes {
            let current = URL(fileURLWithPath: storeURL.path + suffix)
            let copied = backup.appendingPathComponent(current.lastPathComponent)
            if (try? Data(contentsOf: current)) != (try? Data(contentsOf: copied)) {
                return false
            }
        }
        return true
    }

    /// Which generation folders survive rotation. Pure on names, so every
    /// retention rule is testable without touching a disk.
    static func survivors(of names: [String], keep: Int, dailyDays: Int,
                          now: Date) -> Set<String> {
        let sorted = names.sorted()          // stamps sort chronologically
        var keepers = Set(sorted.suffix(keep))

        // "billing-YYYYMMDD-HHMMSS" → the day, or nil. A name that does not
        // parse is NEVER deleted: destroying what cannot be classified is
        // how a rotation bug eats a backup.
        func day(of name: String) -> Substring? {
            let stamp = name.dropFirst("billing-".count)
            let day = stamp.prefix(8)
            guard day.count == 8, day.allSatisfy(\.isNumber),
                  stamp.dropFirst(8).first == "-" else { return nil }
            return day
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd"
        let cutoff = fmt.string(from: now.addingTimeInterval(-Double(dailyDays) * 86_400))

        var newestPerDay: [Substring: String] = [:]
        for name in sorted {
            guard let d = day(of: name) else { keepers.insert(name); continue }
            if d >= cutoff { newestPerDay[d] = name }   // sorted → last wins
        }
        keepers.formUnion(newestPerDay.values)
        return keepers
    }

    private static func existingBackups(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix("billing-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
