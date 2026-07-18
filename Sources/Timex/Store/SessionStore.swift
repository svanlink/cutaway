import Foundation
import SwiftData

/// SwiftData wrapper: session persistence (with midnight splitting) and
/// per-project aggregation. Totals are always recomputed from sessions.
@MainActor
final class SessionStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
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

    /// Deletes a project. Sessions either move to `reassignTo` or fall to the
    /// cascade delete — the caller decides, explicitly.
    func delete(_ project: Project, reassignTo target: Project?) throws {
        if let target {
            for s in project.sessions { s.project = target }
        }
        context.delete(project)
        try context.save()
    }

    // MARK: - Sessions

    /// Persists a closed session, splitting at midnight so day totals stay true.
    func record(_ record: SessionRecord, to project: Project, calendar: Calendar = .current) throws {
        for part in DaySplitter.split(record, calendar: calendar) where part.activeSeconds > 0 {
            context.insert(WorkSession(start: part.start, end: part.end,
                                       activeSeconds: part.activeSeconds, project: project))
        }
        try context.save()
    }

    // MARK: - Aggregation

    func totalActiveSeconds(for project: Project) -> TimeInterval {
        project.sessions.reduce(0) { $0 + $1.activeSeconds }
    }

    func activeSecondsToday(for project: Project, calendar: Calendar = .current, now: Date = Date()) -> TimeInterval {
        let today = calendar.startOfDay(for: now)
        return project.sessions
            .filter { calendar.startOfDay(for: $0.start) == today }
            .reduce(0) { $0 + $1.activeSeconds }
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
                lastEnd: sessions.map(\.end).max() ?? day
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
