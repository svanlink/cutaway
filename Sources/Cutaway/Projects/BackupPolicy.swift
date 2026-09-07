import Foundation

/// When the running app backs itself up. The launch backup covers a relaunch;
/// this covers the weeks in between.
enum BackupPolicy {
    static let interval: TimeInterval = 24 * 3600
    /// How often the app asks whether a backup is due.
    static let checkEvery: TimeInterval = 30 * 60

    static func isDue(last: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
