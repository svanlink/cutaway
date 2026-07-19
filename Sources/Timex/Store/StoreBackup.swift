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

        // Skip when unchanged: byte-compare the main store file against the
        // newest backup's copy (stores are small; simplicity beats hashing).
        if let newest = existingBackups(in: backupsDir).last,
           let prev = try? Data(contentsOf: newest.appendingPathComponent(storeURL.lastPathComponent)),
           let cur = try? Data(contentsOf: storeURL),
           prev == cur {
            return nil
        }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dest = backupsDir.appendingPathComponent("billing-\(fmt.string(from: now))")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
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

    private static func existingBackups(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix("billing-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
