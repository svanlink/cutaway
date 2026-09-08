import Foundation

/// When the running app backs itself up. The launch backup covers a relaunch;
/// this covers the weeks in between.
enum BackupPolicy {
    static let interval: TimeInterval = 24 * 3600
    // No `checkEvery`: the question is asked on the engine's own tick, so
    // the app has exactly one repeating timer. Answering it costs a date
    // comparison — no I/O — so asking every second is cheaper than a
    // second timer that has to be scheduled, coalesced and invalidated.

    static func isDue(last: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
