import Foundation
import SwiftData

/// SwiftData wrapper: session persistence (with midnight splitting) and
/// per-project aggregation. Totals are always recomputed from sessions.
@MainActor
final class SessionStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    /// Today's total per project, memoised. The menu-bar panel renders a row
    /// per project on every tick, and each row asked for this — so the app
    /// re-filtered every project's ENTIRE history twice a second, a cost that
    /// grows with exactly the thing the app is for: months of tracked work.
    private var todayCache: [PersistentIdentifier: (day: Date, seconds: TimeInterval)] = [:]

    /// Diagnostics only: counts the scans that actually touched history, so a
    /// test can prove rendering does not re-walk it.
    private(set) var sessionScanCount = 0

    init(inMemory: Bool = false, url: URL? = nil) throws {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        } else if let url {
            // Explicit location — used to prove that a restored backup really
            // opens and still holds the work someone invoiced against.
            config = ModelConfiguration(url: url)
        } else if let dir = ScenarioMode.dataDir {
            // Verification runs live in their own quarantined store — the
            // real billing database is untouchable from scenario mode.
            let url = URL(fileURLWithPath: dir).appendingPathComponent("timex.store")
            config = ModelConfiguration(url: url)
        } else {
            config = ModelConfiguration(isStoredInMemoryOnly: false)
        }
        container = try ModelContainer(for: Project.self, WorkSession.self, configurations: config)
    }

    // MARK: - Projects

    func projects() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @discardableResult
    func createProject(name: String, client: String, mode: BillingMode,
                       hourlyRate: Double, budget: Double = 0,
                       currency: TimexCurrency) throws -> Project {
        let p = Project(name: name, client: client, mode: mode,
                        hourlyRate: hourlyRate, budget: budget, currency: currency)
        context.insert(p)
        try context.save()
        return p
    }

    func rename(_ project: Project, to newName: String) throws {
        project.name = newName
        try context.save()
    }

    func update(_ project: Project, _ mutate: (Project) -> Void) throws {
        mutate(project)
        try context.save()
    }

    /// Deletes a project. Sessions either move to `reassignTo` or fall to the
    /// cascade delete — the caller decides, explicitly.
    func delete(_ project: Project, reassignTo target: Project?) throws {
        if let target {
            for s in project.sessions { s.project = target }
        }
        context.delete(project)
        try context.save()
        invalidateTodayCache()
    }

    // MARK: - Sessions

    /// Persists a closed session, splitting at midnight so day totals stay true.
    func record(_ record: SessionRecord, to project: Project, calendar: Calendar = .current) throws {
        // Stamp the rate NOW. A raise next month must not reprice this work.
        let rate = project.hourlyRate
        for part in DaySplitter.split(record, calendar: calendar) where part.activeSeconds > 0 {
            context.insert(WorkSession(start: part.start, end: part.end,
                                       activeSeconds: part.activeSeconds,
                                       hourlyRate: rate, project: project))
        }
        try context.save()
        invalidateTodayCache()
    }

    /// Manual correction of one day's total. Growing the day appends a single
    /// zero-span adjustment pinned to the day's last activity; shrinking it
    /// trims the newest sessions first and deletes any that reach zero. The
    /// day's first/last activity survives, so the CSV still tells the truth
    /// about WHEN the work happened.
    /// ponytail: adjustments count as a session in the CSV's session column.
    func setActiveSeconds(_ target: TimeInterval, on day: Date, for project: Project,
                          calendar: Calendar = .current, now: Date = Date()) throws {
        let dayStart = calendar.startOfDay(for: day)
        let sessions = project.sessions
            .filter { calendar.startOfDay(for: $0.start) == dayStart }
            .sorted { $0.end < $1.end }
        let current = sessions.reduce(0) { $0 + $1.activeSeconds }
        var delta = max(0, target) - current
        if delta > 0 {
            let noon = dayStart.addingTimeInterval(12 * 3600)
            let anchor = sessions.last?.end ?? min(noon, now)
            context.insert(WorkSession(start: anchor, end: anchor, activeSeconds: delta,
                                       hourlyRate: project.hourlyRate, project: project,
                                       isAdjusted: true))
        } else {
            for s in sessions.reversed() where delta < 0 {
                let cut = min(s.activeSeconds, -delta)
                s.activeSeconds -= cut
                delta += cut
                if s.activeSeconds <= 0 { context.delete(s) }
            }
        }
        try context.save()
        invalidateTodayCache()
    }

    // MARK: - Aggregation

    /// Newest closed session — the durable receipt behind the menu-bar
    /// "Last session" line. Ordered by `end`: a midnight-split session's
    /// second half is the one the user actually finished.
    func lastSession(for project: Project) -> WorkSession? {
        project.sessions.max { $0.end < $1.end }
    }

    func totalActiveSeconds(for project: Project) -> TimeInterval {
        project.sessions.reduce(0) { $0 + $1.activeSeconds }
    }

    /// Summed from each session's own rate — never from the project's current
    /// one, which is what used to rewrite invoiced history.
    func totalEarned(for project: Project) -> Double {
        project.sessions.reduce(0) { $0 + $1.earned(projectRate: project.hourlyRate) }
    }

    func activeSecondsToday(for project: Project, calendar: Calendar = .current, now: Date = Date()) -> TimeInterval {
        let today = calendar.startOfDay(for: now)
        let id = project.persistentModelID
        // The day is part of the key, so midnight invalidates itself.
        if let cached = todayCache[id], cached.day == today { return cached.seconds }
        sessionScanCount += 1
        let seconds = project.sessions
            .filter { calendar.startOfDay(for: $0.start) == today }
            .reduce(0) { $0 + $1.activeSeconds }
        todayCache[id] = (today, seconds)
        return seconds
    }

    /// Anything that changes what a day contains drops the memo. Wholesale
    /// rather than per-project: writes are rare, renders are not, and a
    /// too-clever invalidation is how a billing figure goes quietly stale.
    private func invalidateTodayCache() {
        todayCache.removeAll()
    }

    /// The individual sessions behind one Daily Breakdown row, in the order
    /// they were worked. Midnight-split halves are already separate rows, so
    /// grouping by `start` day matches what the day total counted.
    func sessions(for project: Project, on day: Date, calendar: Calendar = .current) -> [WorkSession] {
        let target = calendar.startOfDay(for: day)
        return project.sessions
            .filter { calendar.startOfDay(for: $0.start) == target }
            .sorted { $0.start < $1.start }
    }

    /// Daily Breakdown rows, newest first. One entry per worked day.
    func dayTotals(for project: Project, calendar: Calendar = .current) -> [DayTotal] {
        let grouped = Dictionary(grouping: project.sessions) { calendar.startOfDay(for: $0.start) }
        return grouped.map { day, sessions in
            DayTotal(
                day: day,
                activeSeconds: sessions.reduce(0) { $0 + $1.activeSeconds },
                sessionCount: sessions.count,
                firstStart: sessions.map(\.start).min() ?? day,
                lastEnd: sessions.map(\.end).max() ?? day,
                earned: sessions.reduce(0) { $0 + $1.earned(projectRate: project.hourlyRate) },
                adjustedSeconds: sessions.filter { $0.isAdjusted }.reduce(0) { $0 + $1.activeSeconds }
            )
        }
        .sorted { $0.day > $1.day }
    }

    func avgDailySeconds(for project: Project, calendar: Calendar = .current) -> TimeInterval {
        let totals = dayTotals(for: project, calendar: calendar)
        guard !totals.isEmpty else { return 0 }
        return totals.reduce(0) { $0 + $1.activeSeconds } / Double(totals.count)
    }
}
