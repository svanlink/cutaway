import Foundation

/// Launch-time billing-data backup: copies the SwiftData store trio
/// (.store, -wal, -shm) into a stamped folder under Backups/, skips when
/// nothing changed, and keeps only the newest `keep` backups.
/// Runs BEFORE the container opens, so the files are quiescent.
enum StoreBackup {
    static let defaultKeep = 7

    /// Returns the created backup directory, or nil when skipped.
    @discardableResult
    static func backUp(storeURL: URL, backupsDir: URL, now: Date = Date(),
                       keep: Int = defaultKeep) throws -> URL? {
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
           matchesBackup(storeURL: storeURL, backup: newest) {
            return nil
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dest = backupsDir.appendingPathComponent("billing-\(fmt.string(from: now))")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for suffix in copiedSuffixes {
            let src = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: dest.appendingPathComponent(src.lastPathComponent))
        }

        // Rotate: stamped names sort lexically, oldest first.
        let all = existingBackups(in: backupsDir)
        for stale in all.dropLast(keep) {
            try? fm.removeItem(at: stale)
        }
        return dest
    }

    /// `-shm` is a derived index, rebuilt from the other two — copied for
    /// completeness, never consulted when deciding whether anything changed.
    private static let dataSuffixes = ["", "-wal"]
    private static let copiedSuffixes = ["", "-wal", "-shm"]

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

    private static func existingBackups(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix("billing-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
