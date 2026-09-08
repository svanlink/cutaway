import Foundation

/// The geometry and arithmetic of a day's strip, with no view attached.
///
/// Everything here decides where a block sits, what a drag lands on, and how
/// a split divides money. That last one is why this is a separate, tested
/// type rather than maths inside a gesture handler.
struct DayTimeline: Equatable {

    struct Block: Identifiable, Equatable {
        var id: String
        var start: Date
        var end: Date
        var activeSeconds: TimeInterval
        var isAdjusted: Bool
        var isLive: Bool = false

        var span: TimeInterval { max(end.timeIntervalSince(start), 0) }
        /// Time inside the span that was NOT worked — the gap the idle rule
        /// took out. Shown, never hidden: it is why hours and span differ.
        var idleSeconds: TimeInterval { max(span - activeSeconds, 0) }
    }

    let start: Date
    let end: Date
    var blocks: [Block]

    var duration: TimeInterval { max(end.timeIntervalSince(start), 1) }

    /// A working day, not a calendar day.
    ///
    /// An editor's day is six hours wide; drawing 00:00–24:00 turns every
    /// session into a sliver of a mostly-empty axis. The domain runs from the
    /// hour containing the first start to the hour containing the last end,
    /// with a four-hour floor so a single short session still has a scale.
    static func domain(for blocks: [Block], on day: Date, calendar: Calendar = .current,
                       minimumHours: Int = 4) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: day)
        guard let first = blocks.map(\.start).min(), let last = blocks.map(\.end).max() else {
            // Empty day: a plausible working window rather than midnight.
            let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
            let five = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: dayStart) ?? dayStart
            return (nine, five)
        }
        var from = calendar.dateInterval(of: .hour, for: first)?.start ?? first
        var to = calendar.dateInterval(of: .hour, for: last)?.end ?? last
        // Grow to the floor around the middle, so a 20-minute day is centred
        // rather than pinned to its first hour.
        let floor = TimeInterval(minimumHours) * 3600
        if to.timeIntervalSince(from) < floor {
            let missing = floor - to.timeIntervalSince(from)
            from = from.addingTimeInterval(-missing / 2)
            to = to.addingTimeInterval(missing / 2)
        }
        return (from, to)
    }

    func fraction(of date: Date) -> Double {
        min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }

    func date(atFraction f: Double) -> Date {
        start.addingTimeInterval(duration * min(max(f, 0), 1))
    }

    /// Five minutes by default; one with ⌥. A drag that lands on 11:37:42 is
    /// noise being recorded as precision.
    static func snap(_ date: Date, toMinutes minutes: Int) -> Date {
        let step = TimeInterval(minutes * 60)
        return Date(timeIntervalSinceReferenceDate:
                        (date.timeIntervalSinceReferenceDate / step).rounded() * step)
    }

    /// Hour marks, thinned until they stop colliding. Every hour up to eight,
    /// then every second hour, then every fourth.
    static func tickInterval(hours: Double) -> Int {
        switch hours {
        case ...8: return 1
        case ..<14: return 2
        default: return 4
        }
    }

    func ticks(calendar: Calendar = .current) -> [Date] {
        let step = Self.tickInterval(hours: duration / 3600)
        var result: [Date] = []
        var t = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        if t <= start { t = t.addingTimeInterval(3600) }
        while t <= end {
            result.append(t)
            t = t.addingTimeInterval(TimeInterval(step) * 3600)
        }
        return result
    }

    /// Gaps worth drawing. Under twenty minutes a gap is the bridge doing its
    /// job, not something to explain.
    static func gaps(in blocks: [Block], longerThan seconds: TimeInterval = 20 * 60)
        -> [(start: Date, end: Date)] {
        let sorted = blocks.sorted { $0.start < $1.start }
        return zip(sorted, sorted.dropFirst()).compactMap { a, b in
            b.start.timeIntervalSince(a.end) > seconds ? (a.end, b.start) : nil
        }
    }

    // MARK: - Splitting

    /// Divide one session at a moment, distributing its ACTIVE seconds by
    /// wall-clock fraction.
    ///
    /// The arithmetic matters: a two-hour span holding 90 minutes of active
    /// time, split at its midpoint, becomes two one-hour spans of 45 minutes
    /// each — not two of 60. The idle the engine already excluded stays
    /// excluded, and the two halves still add up to what the day billed.
    static func split(_ block: Block, at moment: Date) -> (first: Block, second: Block)? {
        guard moment > block.start, moment < block.end, block.span > 0 else { return nil }
        let fraction = moment.timeIntervalSince(block.start) / block.span
        var first = block
        var second = block
        first.end = moment
        first.activeSeconds = (block.activeSeconds * fraction).rounded()
        second.id = block.id + "-b"
        second.start = moment
        // The remainder, not a second rounding — the two halves must sum to
        // exactly what the whole billed.
        second.activeSeconds = block.activeSeconds - first.activeSeconds
        return (first, second)
    }

    /// What the caption under the strip says.
    static func summary(_ blocks: [Block]) -> (sessions: Int, tracked: TimeInterval, gaps: TimeInterval) {
        let tracked = blocks.reduce(0) { $0 + $1.activeSeconds }
        let gapSeconds = gaps(in: blocks, longerThan: 0).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return (blocks.count, tracked, gapSeconds)
    }
}
