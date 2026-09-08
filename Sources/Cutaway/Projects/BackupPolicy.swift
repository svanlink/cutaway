import Foundation

/// When the running app backs itself up. The launch backup covers a relaunch;
/// this covers the weeks in between.
enum BackupPolicy {
    // Hourly, not daily. This app runs for weeks at a stretch, so a daily
    // tick meant up to 22 hours of billable work sat between the newest
    // generation and now — a full working day, at this owner's day lengths.
    // The snapshot is a VACUUM INTO of a 94 KB file, and `isUnchanged`
    // already suppresses a folder when nothing has changed, so the cost of
    // asking more often is close to nothing.
    static let interval: TimeInterval = 3600
    // No `checkEvery`: the question is asked on the engine's own tick, so
    // the app has exactly one repeating timer. Answering it costs a date
    // comparison — no I/O — so asking every second is cheaper than a
    // second timer that has to be scheduled, coalesced and invalidated.

    static func isDue(last: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
