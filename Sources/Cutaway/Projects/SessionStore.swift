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

    /// Save, or leave the context exactly as it was found.
    ///
    /// Every mutator here follows the shape *mutate the objects → save*, and
    /// nothing used to roll back. A throwing `save()` therefore left the
    /// in-memory graph holding the edit while the banner said the edit had
    /// not been saved — and since every reading surface (day totals, the
    /// strip, the unbilled figure, the invoice builder) reads those same
    /// objects, the screen showed a state the disk did not have. The main
    /// context autosaves, so the mutation the banner disclaimed could still
    /// be committed a moment later, or lost at quit; which of the two
    /// happened was invisible.
    ///
    /// `setActiveSeconds` was the sharp end: it calls `context.delete` on
    /// real recorded sessions before saving, so a failed save left them
    /// deleted on screen under a banner claiming nothing had happened.
    func commit() throws {
        do { try context.save() } catch { context.rollback(); throw error }
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
        try commit()
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
        try commit()
    }

    func update(_ project: Project, _ mutate: (Project) -> Void) throws {
        mutate(project)
        try commit()
    }

    /// Deletes a project. Sessions either move to `reassignTo` or fall to the
    /// cascade delete — the caller decides, explicitly.
    func delete(_ project: Project, reassignTo target: Project?) throws {
        // The cascade would take sessions an issued invoice claims with it,
        // leaving a document nobody can prove. `assertNothingInvoiced` had no
        // production caller at all until now.
        if target == nil { try assertNothingInvoiced(in: project) }
        if let target {
            for s in project.sessions { s.project = target }
        }
        context.delete(project)
        try commit()
        invalidateTodayCache()
    }

    // MARK: - Sessions

    /// Persists a closed session, splitting at midnight so day totals stay true.
    /// - Parameters:
    ///   - uid: a stable identity for work that may be written more than
    ///     once. SwiftData's `save()` can throw AFTER the row has landed, so
    ///     the failed-save journal can hold work the store already has —
    ///     replaying it without this billed the same hours twice.
    ///   - rate: the rate it was WORKED at. Defaults to the project's current
    ///     rate, which is right for a session closing now and wrong for one
    ///     replayed from the journal after a raise.
    func record(_ record: SessionRecord, to project: Project,
                uid: String? = nil, rate: Double? = nil,
                calendar: Calendar = .current) throws {
        if let uid, project.sessions.contains(where: { $0.uid.hasPrefix(uid) }) {
            return   // already stored; a replay is not a second piece of work
        }
        // Stamp the rate NOW. A raise next month must not reprice this work.
        let rate = rate ?? project.hourlyRate
        for (index, part) in DaySplitter.split(record, calendar: calendar)
            .filter({ $0.activeSeconds > 0 }).enumerated() {
            let session = WorkSession(start: part.start, end: part.end,
                                      activeSeconds: part.activeSeconds,
                                      hourlyRate: rate, project: project)
            // A span across midnight becomes several rows; they share the
            // journal's identity so the whole span is replay-safe together.
            if let uid { session.uid = "\(uid)-\(index)" }
            context.insert(session)
        }
        try commit()
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
        // A typed span must not sit on top of work that is already recorded.
        // Found live on 2026-09-08: a typed 10:00-18:00 day covering two
        // tracked sessions, and the day billed both. Half-open comparison, so
        // a 09:00-12:00 morning and a 12:00-17:00 afternoon still touch
        // legally. Only this project's own sessions — two clients at once is
        // a different argument, and not this one.
        if let clash = project.sessions.first(where: { $0.start < end && start < $0.end }) {
            throw SessionEditError.overlapsExisting(clash.start)
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
        try commit()
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
        // …and on the day it was already on.
        //
        // The check above only asks that the new start and end share A day,
        // not that it is the SAME day. The edit sheet cannot break that — its
        // Day picker is disabled while editing — but the strip's drag has no
        // day clamp, and a long enough drag walks a block into tomorrow.
        // Undo is what makes that expensive: `dayEdit` snapshots exactly one
        // day, so restoring the old day re-inserts the block while the moved
        // copy sits untouched on the next day. One gesture and one Cmd-Z
        // turned four billable hours into eight.
        guard calendar.startOfDay(for: start) == calendar.startOfDay(for: session.start) else {
            throw SessionEditError.leavesItsDay
        }
        // Nor on top of work that is already there.
        //
        // `addSession` has refused overlap since a typed 10:00–18:00 day was
        // found sitting over two tracked sessions with the day billing all
        // three. `updateSession` is the other way a span gets its times and
        // had no such check: dragging a 3 h morning onto a 4 h afternoon left
        // seven billable hours inside a four-hour window — on the CSV, on the
        // invoice, and undefendable on a phone call.
        if let clash = project.sessions.first(where: {
            $0.persistentModelID != session.persistentModelID && $0.start < end && start < $0.end
        }) {
            throw SessionEditError.overlapsExisting(clash.start)
        }
        // Active time SCALES with the span; it is not the span.
        //
        // Setting it to the new span invented money on every move: a session
        // from 13:00 to 17:00 holding 2 h 30 of actual work — the rest was
        // idle the engine already excluded — became four billable hours the
        // moment it was dragged sideways. CHF 300 turned into CHF 480 with a
        // gesture that was supposed to change WHEN, not how much.
        let oldSpan = session.end.timeIntervalSince(session.start)
        let newSpan = end.timeIntervalSince(start)
        let ratio = oldSpan > 0 ? newSpan / oldSpan : 1
        session.start = start
        session.end = end
        // Never more than the span itself, and never conjured out of a
        // zero-length original.
        session.activeSeconds = min(session.activeSeconds * ratio, newSpan)
        session.isAdjusted = true
        try commit()
        invalidateTodayCache()
    }

    /// Remove one session outright — the timer ran while nobody worked.
    func deleteSession(_ session: WorkSession, calendar: Calendar = .current) throws {
        if let project = session.project,
           let number = invoiceNumber(coveringDay: session.start, for: project, calendar: calendar) {
            throw InvoiceError.dayIsInvoiced(number)
        }
        context.delete(session)
        try commit()
        invalidateTodayCache()
    }

    /// Cut one session in two at a moment on the strip.
    ///
    /// Active seconds are distributed by wall-clock fraction and the second
    /// half takes the REMAINDER, so the two together bill exactly what the
    /// one did. Splitting is how a day gets divided between two clients:
    /// split, then reassign one half.
    @discardableResult
    func splitSession(_ session: WorkSession, at moment: Date,
                      calendar: Calendar = .current) throws -> WorkSession {
        guard let project = session.project else { throw SessionEditError.endBeforeStart }
        if let number = invoiceNumber(coveringDay: session.start, for: project, calendar: calendar) {
            throw InvoiceError.dayIsInvoiced(number)
        }
        let block = DayTimeline.Block(id: "s", start: session.start, end: session.end,
                                      activeSeconds: session.activeSeconds,
                                      isAdjusted: session.isAdjusted)
        guard let halves = DayTimeline.split(block, at: moment) else {
            throw SessionEditError.splitOutsideSession
        }
        session.end = halves.first.end
        session.activeSeconds = halves.first.activeSeconds
        let second = WorkSession(start: halves.second.start, end: halves.second.end,
                                 activeSeconds: halves.second.activeSeconds,
                                 hourlyRate: session.hourlyRate, project: project,
                                 isAdjusted: session.isAdjusted)
        context.insert(second)
        try commit()
        invalidateTodayCache()
        return second
    }

    /// Move one session to another project — the other half of splitting a
    /// day between two clients. The rate travels with the DESTINATION only if
    /// the session never had one of its own; work already stamped keeps the
    /// rate it was worked at.
    func reassign(_ session: WorkSession, to project: Project,
                  calendar: Calendar = .current) throws {
        for candidate in [session.project, project].compactMap({ $0 }) {
            if let number = invoiceNumber(coveringDay: session.start, for: candidate, calendar: calendar) {
                throw InvoiceError.dayIsInvoiced(number)
            }
        }
        if session.hourlyRate <= 0 { session.hourlyRate = project.hourlyRate }
        session.project = project
        try commit()
        invalidateTodayCache()
    }

    enum SessionEditError: LocalizedError {
        case endBeforeStart
        case spansMidnight
        case leavesItsDay
        case splitOutsideSession
        case overlapsExisting(Date)

        var errorDescription: String? {
            switch self {
            case .endBeforeStart:
                return String(localized: "The end has to come after the start.")
            case .overlapsExisting(let start):
                let when = start.formatted(date: .omitted, time: .shortened)
                return String(localized: "That span already holds work recorded at \(when). Change the span, or edit the session that is already there.")
            case .splitOutsideSession:
                return String(localized: "Split at a moment inside the session.")
            case .spansMidnight:
                // Splitting on edit would turn one row into two under the
                // owner's hands. Adding across midnight is fine — that path
                // splits deliberately.
                return String(localized: "A session has to end on the day it started. Add a second one after midnight.")
            case .leavesItsDay:
                return String(localized: "A session stays on its own day. Delete it and add one on the day you meant.")
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
                                   hourlyRate: $0.hourlyRate, isAdjusted: $0.isAdjusted,
                                   uid: $0.uid, invoiceNumber: $0.invoiceNumber) }
        return DayEdit(day: dayStart, sessions: sessions, name: name)
    }

    /// Put a day back exactly as `dayEdit` found it.
    func restore(_ edit: DayEdit, for project: Project, calendar: Calendar = .current) throws {
        let dayStart = calendar.startOfDay(for: edit.day)
        // An issued invoice outranks an undo: the document is already with
        // the client, and the store must not quietly disagree with it.
        if let number = invoiceNumber(coveringDay: dayStart, for: project, calendar: calendar) {
            throw InvoiceError.dayIsInvoiced(number)
        }
        for session in project.sessions where calendar.startOfDay(for: session.start) == dayStart {
            context.delete(session)
        }
        for s in edit.sessions {
            let restored = WorkSession(start: s.start, end: s.end, activeSeconds: s.activeSeconds,
                                       hourlyRate: s.hourlyRate, project: project, isAdjusted: s.isAdjusted)
            // Identity and the lock come back with the work. Without them an
            // undo unlocked an invoiced day and orphaned the invoice's
            // provenance.
            restored.uid = s.uid
            restored.invoiceNumber = s.invoiceNumber
            context.insert(restored)
        }
        try commit()
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
        try commit()
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
        Self.dayTotals(from: project.sessions, projectRate: project.hourlyRate, calendar: calendar)
    }

    /// Day rows over a GIVEN set of sessions.
    ///
    /// The invoice needs this: it bills only sessions that are not already on
    /// an invoice, and grouping the project's whole history instead meant a
    /// day that was partly invoiced got billed again IN FULL. Two hours
    /// invoiced and one added later produced a line for three.
    static func dayTotals(from sessions: [WorkSession], projectRate: Double,
                          calendar: Calendar = .current) -> [DayTotal] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
        return grouped.map { day, sessions in
            DayTotal(
                day: day,
                activeSeconds: sessions.reduce(0) { $0 + $1.activeSeconds },
                sessionCount: sessions.count,
                firstStart: sessions.map(\.start).min() ?? day,
                lastEnd: sessions.map(\.end).max() ?? day,
                earned: sessions.reduce(0) { $0 + $1.earned(projectRate: projectRate) },
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
