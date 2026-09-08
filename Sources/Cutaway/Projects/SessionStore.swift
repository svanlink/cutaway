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
        } else {
            // Named and quarantined by policy — never the shared default.store.
            let url = StorePath.url()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            config = ModelConfiguration(url: url)
        }
        // Inferred, NOT staged. See Schema.swift: a declared plan makes
        // SwiftData reject any store whose model version it does not know,
        // and every store written before the declaration is exactly that.
        container = try ModelContainer(for: Project.self, WorkSession.self,
                                       Invoice.self, InvoiceLine.self,
                                       configurations: config)
    }

    // MARK: - Projects

    func projects() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    @discardableResult
    func createProject(name: String, client: String, mode: BillingMode,
                       hourlyRate: Double, budget: Double = 0,
                       currency: BillingCurrency, appBundleIDs: [String] = []) throws -> Project {
        let p = Project(name: name, client: client, mode: mode,
                        hourlyRate: hourlyRate, budget: budget, currency: currency,
                        appBundleIDs: appBundleIDs)
        context.insert(p)
        try context.save()
        return p
    }

    /// Deleting work that an invoice claims would leave the document
    /// unprovable. Refused by number, so the message says which one.
    func assertNothingInvoiced(in project: Project) throws {
        if let locked = project.sessions.first(where: \.isInvoiced) {
            throw InvoiceError.sessionsAreInvoiced(locked.invoiceNumber)
        }
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

    /// A session entered by hand as a SPAN — "I worked 09:00 to 12:00".
    ///
    /// The honest unit. Setting a day's total has to invent a moment for the
    /// time to sit at (the old editor pinned it to noon), so the CSV could
    /// say a day held four hours without being able to say when. A span says
    /// when, and `first/last activity` on an invoice stays true.
    ///
    /// Marked adjusted, like every typed figure: it reaches the CSV's
    /// `adjusted_hours` column and the invoice's footnote.
    @discardableResult
    func addSession(from start: Date, to end: Date, for project: Project,
                    calendar: Calendar = .current) throws -> [WorkSession] {
        guard end > start else {
            throw SessionEditError.endBeforeStart
        }
        if let number = invoiceNumber(coveringDay: start, for: project, calendar: calendar) {
            throw InvoiceError.dayIsInvoiced(number)
        }
        let record = SessionRecord(start: start, end: end, activeSeconds: end.timeIntervalSince(start))
        var inserted: [WorkSession] = []
        let rate = project.hourlyRate
        for part in DaySplitter.split(record, calendar: calendar) where part.activeSeconds > 0 {
            let session = WorkSession(start: part.start, end: part.end,
                                      activeSeconds: part.activeSeconds,
                                      hourlyRate: rate, project: project, isAdjusted: true)
            context.insert(session)
            inserted.append(session)
        }
        try context.save()
        invalidateTodayCache()
        return inserted
    }

    /// Move or resize one recorded session. The hours follow the span: a
    /// session that says 09:00–12:00 and bills two hours is a session nobody
    /// can defend.
    func updateSession(_ session: WorkSession, from start: Date, to end: Date,
                       calendar: Calendar = .current) throws {
        guard end > start else { throw SessionEditError.endBeforeStart }
        guard let project = session.project else { return }
        for day in [session.start, start] {
            if let number = invoiceNumber(coveringDay: day, for: project, calendar: calendar) {
                throw InvoiceError.dayIsInvoiced(number)
            }
        }
        guard calendar.startOfDay(for: start) == calendar.startOfDay(for: end) else {
            throw SessionEditError.spansMidnight
        }
        session.start = start
        session.end = end
        session.activeSeconds = end.timeIntervalSince(start)
        session.isAdjusted = true
        try context.save()
        invalidateTodayCache()
    }

    /// Remove one session outright — the timer ran while nobody worked.
    func deleteSession(_ session: WorkSession, calendar: Calendar = .current) throws {
        if let project = session.project,
           let number = invoiceNumber(coveringDay: session.start, for: project, calendar: calendar) {
            throw InvoiceError.dayIsInvoiced(number)
        }
        context.delete(session)
        try context.save()
        invalidateTodayCache()
    }

    enum SessionEditError: LocalizedError {
        case endBeforeStart
        case spansMidnight

        var errorDescription: String? {
            switch self {
            case .endBeforeStart:
                return String(localized: "The end has to come after the start.")
            case .spansMidnight:
                // Splitting on edit would turn one row into two under the
                // owner's hands. Adding across midnight is fine — that path
                // splits deliberately.
                return String(localized: "A session has to end on the day it started. Add a second one after midnight.")
            }
        }
    }

    /// Manual correction of one day's total. Growing the day appends a single
    /// zero-span adjustment pinned to the day's last activity; shrinking it
    /// trims the newest sessions first and deletes any that reach zero. The
    /// day's first/last activity survives, so the CSV still tells the truth
    /// about WHEN the work happened.
    // MARK: - Undo support

    /// Every session on one day, as plain values — safe to hold across the
    /// edit that is about to destroy some of them.
    func dayEdit(_ day: Date, for project: Project, named name: String,
                 calendar: Calendar = .current) -> DayEdit {
        let dayStart = calendar.startOfDay(for: day)
        let sessions = project.sessions
            .filter { calendar.startOfDay(for: $0.start) == dayStart }
            .sorted { $0.start < $1.start }
            .map { DayEdit.Session(start: $0.start, end: $0.end, activeSeconds: $0.activeSeconds,
                                   hourlyRate: $0.hourlyRate, isAdjusted: $0.isAdjusted) }
        return DayEdit(day: dayStart, sessions: sessions, name: name)
    }

    /// Put a day back exactly as `dayEdit` found it.
    func restore(_ edit: DayEdit, for project: Project, calendar: Calendar = .current) throws {
        let dayStart = calendar.startOfDay(for: edit.day)
        for session in project.sessions where calendar.startOfDay(for: session.start) == dayStart {
            context.delete(session)
        }
        for s in edit.sessions {
            context.insert(WorkSession(start: s.start, end: s.end, activeSeconds: s.activeSeconds,
                                       hourlyRate: s.hourlyRate, project: project, isAdjusted: s.isAdjusted))
        }
        try context.save()
        invalidateTodayCache()
    }

    /// ponytail: adjustments count as a session in the CSV's session column.
    func setActiveSeconds(_ target: TimeInterval, on day: Date, for project: Project,
                          calendar: Calendar = .current, now: Date = Date()) throws {
        // A day on an issued invoice is not editable. The document a client
        // holds and the store must never be able to disagree quietly; the way
        // back is to void the invoice, which says so out loud.
        if let number = invoiceNumber(coveringDay: day, for: project, calendar: calendar) {
            throw InvoiceError.dayIsInvoiced(number)
        }
        let dayStart = calendar.startOfDay(for: day)
        let sessions = project.sessions
            .filter { calendar.startOfDay(for: $0.start) == dayStart }
            .sorted { $0.end < $1.end }
        let current = sessions.reduce(0) { $0 + $1.activeSeconds }
        var delta = max(0, target) - current
        if delta > 0 {
            let noon = dayStart.addingTimeInterval(12 * 3600)
            // Clamped inside the day: an overnight split's last part ends at
            // exactly the next midnight, and a zero-span session there would
            // be grouped onto the following day — every retry adding again.
            let dayEnd = (calendar.date(byAdding: .day, value: 1, to: dayStart)
                          ?? dayStart.addingTimeInterval(86_400)).addingTimeInterval(-1)
            let anchor = min(sessions.last?.end ?? min(noon, now), dayEnd)
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
    // Not private: the invoice extension lives in its own file and locks
    // sessions, which changes what today's figures mean.
    func invalidateTodayCache() {
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
