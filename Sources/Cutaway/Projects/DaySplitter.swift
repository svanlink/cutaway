import Foundation

/// Splits a session crossing midnight into per-day chunks so daily rows and
/// CSV exports attribute time to the correct calendar day. Active seconds are
/// distributed proportionally to wall-clock time in each chunk.
///
/// INVARIANT this depends on: DetectionEngine force-closes open sessions at
/// midnight, so in-app records essentially never span days — this proportional
/// model only handles crash-recovery edge records. If the midnight force-close
/// is ever removed, revisit this distribution model first.
enum DaySplitter {
    static func split(_ record: SessionRecord, calendar: Calendar = .current) -> [SessionRecord] {
        let wallDuration = record.end.timeIntervalSince(record.start)
        guard wallDuration > 0 else { return [record] }

        var parts: [SessionRecord] = []
        var cursor = record.start
        while cursor < record.end {
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else {
                break
            }
            let chunkEnd = min(nextMidnight, record.end)
            let fraction = chunkEnd.timeIntervalSince(cursor) / wallDuration
            parts.append(SessionRecord(
                start: cursor,
                end: chunkEnd,
                activeSeconds: record.activeSeconds * fraction
            ))
            cursor = chunkEnd
        }
        return parts.isEmpty ? [record] : parts
    }
}
