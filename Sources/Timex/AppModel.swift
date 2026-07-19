import Foundation
import SwiftUI
import SwiftData

/// Glue between detection, persistence, and UI. One instance per app.
@Observable
@MainActor
final class AppModel {
    let engine: DetectionEngine
    let store: SessionStore
    let detector = ProjectDetector()

    var selectedProjectID: PersistentIdentifier?
    var showNewProjectSheet = false
    /// Non-nil while the rename / delete sheet is up for that project.
    var renameTarget: Project?
    var deleteTarget: Project?
    var mainTab: MainTab = .timer
    /// The ⌥⌘P registration failed (shortcut conflict) — surfaced in Settings.
    var hotkeyUnavailable = false
    /// Captured from the main window's environment so AppKit surfaces
    /// (status-item panel) can reopen it.
    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?

    var dailyGoalHours: Double {
        get { Prefs.object(forKey: "dailyGoalHours") as? Double ?? 8 }
        set { Prefs.set(newValue, forKey: "dailyGoalHours") }
    }

    init() {
        engine = ScenarioMode.isActive
            ? DetectionEngine(probes: ScenarioDriver.probes)
            : DetectionEngine()
        // Back up the real billing store before it opens (quiescent files).
        // Scenario/demo stores are disposable — never backed up.
        if !ScenarioMode.isActive {
            let storeURL = ModelConfiguration(isStoredInMemoryOnly: false).url
            let backupsDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cutaway/Backups")
            try? StoreBackup.backUp(storeURL: storeURL, backupsDir: backupsDir)
        }
        do {
            store = try SessionStore()
        } catch {
            // SwiftData refusing to open is unrecoverable at runtime; an
            // in-memory store keeps the app alive for this run.
            store = try! SessionStore(inMemory: true)
        }
        // ponytail: TIMEX_DEMO seeds sample data for screenshots/dev runs
        if ProcessInfo.processInfo.environment["TIMEX_DEMO"] != nil,
           (try? store.projects())?.isEmpty == true {
            seedDemoData()
        }
        // Restore last selected project by name (persistentModelID is not
        // stable across launches); fall back to the first project.
        let all = (try? store.projects()) ?? []
        let savedName = Prefs.string(forKey: "selectedProjectName")
        selectedProjectID = (all.first { $0.name == savedName } ?? all.first)?.persistentModelID
        engine.hasActiveProject = selectedProjectID != nil
        engine.onSessionClosed = { [weak self] record in
            guard let self, let project = self.selectedProject else { return }
            try? self.store.record(record, to: project)
            self.flashBankedSession(record.activeSeconds)
        }
        // Crash recovery: persist the last checkpoint of a session that never
        // closed. The snapshot is cleared ONLY after a successful persist —
        // otherwise it survives for the next launch to retry.
        if let crashed = DetectionEngine.peekCrashedSession() {
            if let p = selectedProject, (try? store.record(crashed, to: p)) != nil {
                DetectionEngine.clearCrashedSessionSnapshot()
            }
        }
        // Project auto-switch while recording:
        // Tier 2 (window title) every 5s — cheap AX read.
        // Tier 1 (Studio scripting API) every 30s — spawns fuscript, exact name.
        var tickCount = 0
        var tier1InFlight = false
        engine.onTick = { [weak self] in
            guard let self, !ScenarioMode.isActive else { return }
            // Detection runs while recording AND while paused for lack of a
            // project — that's how a zero-state install bootstraps itself
            // from whatever is open in Resolve.
            let active = self.engine.state == .recording || self.engine.state == .paused(.noProject)
            guard active else { return }
            tickCount += 1
            if tickCount % 5 == 0, let detected = self.detector.detectProjectName() {
                // Tier 2 (window title) may only SELECT — titles can carry
                // suffixes/case drift; letting it create would spawn duplicate
                // projects that silently split billing.
                self.switchOrCreate(detected, canCreate: false)
            }
            // Tier 1 fires fast the first time (tick 3) so a fresh install
            // picks up the open project within seconds. Steady-state interval:
            // spawning fuscript is the app's heaviest periodic cost, so when
            // the cheap Tier 2 (AX) is available it drops to every 120s.
            let tier1Interval = self.detector.accessibilityGranted ? 120 : 30
            if (tickCount == 3 || tickCount % tier1Interval == 0), !tier1InFlight {
                tier1InFlight = true
                Task { [weak self] in
                    let name = await self?.detector.detectViaScriptingAPI()
                    await MainActor.run {
                        tier1InFlight = false
                        // Tier 1 is the exact API name — it may create.
                        if let name { self?.switchOrCreate(name, canCreate: true) }
                    }
                }
            }
        }
        if ScenarioMode.isActive {
            // The driver owns the tick loop and the virtual clock.
            ScenarioDriver.run(model: self)
        } else {
            engine.start()
        }
    }

    /// Scenario hook: same path as a Tier-1 detection.
    func scenarioDetect(_ name: String) {
        switchOrCreate(name, canCreate: true)
    }

    func rename(_ project: Project, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? store.rename(project, to: name)
        if project.persistentModelID == selectedProjectID {
            Prefs.set(name, forKey: "selectedProjectName")
        }
        invalidateProjectCache()
    }

    func delete(_ project: Project, reassignTo target: Project?) {
        let wasSelected = project.persistentModelID == selectedProjectID
        if wasSelected {
            // The open span belongs to the project being deleted (or its heir).
            engine.closeSessionNow(reason: "project-delete")
        }
        try? store.delete(project, reassignTo: target)
        invalidateProjectCache()
        if wasSelected {
            selectedProjectID = (target ?? projects.first)?.persistentModelID
            Prefs.set(selectedProject?.name, forKey: "selectedProjectName")
            engine.hasActiveProject = selectedProjectID != nil
        }
    }

    private func seedDemoData() {
        let cal = Calendar.current
        guard let nyx = try? store.createProject(name: "Nyx Fashion Film", client: "Nyx Studios",
                                                 mode: .hourly, hourlyRate: 85, currency: .chf),
              let alpina = try? store.createProject(name: "Alpina Ski Promo", client: "Alpina Sports",
                                                    mode: .budget, hourlyRate: 85, budget: 4500, currency: .chf)
        else { return }
        let today = cal.startOfDay(for: Date())
        let fixtures: [(Project, Int, Double)] = [
            (nyx, 0, 4.6), (nyx, 1, 6.9), (nyx, 2, 5.2), (nyx, 3, 3.1), (nyx, 6, 7.6),
            (alpina, 0, 2.4), (alpina, 2, 5.8), (alpina, 5, 4.9),
        ]
        for (project, daysAgo, hoursWorked) in fixtures {
            guard let day = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let start = day.addingTimeInterval(10 * 3600)
            let rec = SessionRecord(start: start,
                                    end: start.addingTimeInterval(hoursWorked * 3600 + 1800),
                                    activeSeconds: hoursWorked * 3600)
            try? store.record(rec, to: project)
        }
    }

    // Cached — fetching per access ran a full fetch several times per tick.
    private var cachedProject: Project?

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        if let cached = cachedProject, cached.persistentModelID == id { return cached }
        cachedProject = (try? store.projects())?.first { $0.persistentModelID == id }
        return cachedProject
    }

    // Cached — the panel re-renders every tick; refetching per render ran a
    // full SwiftData fetch twice a second.
    private var cachedProjects: [Project]?

    var projects: [Project] {
        if let cached = cachedProjects { return cached }
        let list = (try? store.projects()) ?? []
        cachedProjects = list
        return list
    }

    private func invalidateProjectCache() {
        cachedProjects = nil
        cachedProject = nil
    }

    /// Switch attribution to the detected Resolve project — creating it (Tier 1
    /// only) with the default rate/currency if Timex hasn't seen it before.
    /// Matching is normalized (trim + case/diacritic-insensitive) so tier
    /// disagreements can't spawn duplicate projects.
    private func switchOrCreate(_ detectedName: String, canCreate: Bool) {
        let name = detectedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        func normalized(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespaces)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        if let match = projects.first(where: { normalized($0.name) == normalized(name) }) {
            if match.persistentModelID != selectedProjectID { select(match) }
            return
        }
        guard canCreate else { return }
        let d = Prefs
        let currency = TimexCurrency(rawValue: d.string(forKey: "defaultCurrency") ?? "CHF") ?? .chf
        let rate = d.object(forKey: "defaultHourlyRate") as? Double ?? 85
        createProject(name: name, client: "", mode: .hourly, rate: rate, budget: 0, currency: currency)
    }

    func select(_ project: Project) {
        guard project.persistentModelID != selectedProjectID else { return }
        // Close the running span first so its time stays with the old project.
        engine.closeSessionNow(reason: "project-switch")
        selectedProjectID = project.persistentModelID
        engine.hasActiveProject = true
        Prefs.set(project.name, forKey: "selectedProjectName")
    }

    func createProject(name: String, client: String, mode: BillingMode,
                       rate: Double, budget: Double, currency: TimexCurrency) {
        guard let p = try? store.createProject(name: name, client: client, mode: mode,
                                               hourlyRate: rate, budget: budget, currency: currency) else { return }
        invalidateProjectCache()
        select(p)
        engine.hasActiveProject = true
    }

    // MARK: - Live figures (persisted + running accumulator)

    var todaySeconds: TimeInterval {
        let persisted = selectedProject.map { store.activeSecondsToday(for: $0) } ?? 0
        return persisted + engine.accumulator.activeSeconds
    }

    var todayMoney: String {
        guard let p = selectedProject else { return "—" }
        return p.currency.format(BillingEngine.earnings(activeSeconds: todaySeconds, hourlyRate: p.hourlyRate))
    }

    var goalProgress: BillingEngine.GoalProgress {
        BillingEngine.goalProgress(activeSeconds: todaySeconds, goalSeconds: dailyGoalHours * 3600)
    }

    var isPausedVisual: Bool { engine.state != .recording }

    /// What the menu-bar pill displays, per the "Menu bar shows" setting.
    /// Peak-end moment: a closed session is the billing event — the pill
    /// quietly confirms it for a few seconds instead of staying silent.
    var bankedFlash: String?

    func flashBankedSession(_ activeSeconds: TimeInterval) {
        guard activeSeconds >= 60 else { return }  // micro-sessions stay quiet
        let text = Self.bankedText(activeSeconds)
        bankedFlash = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.bankedFlash == text { self?.bankedFlash = nil }
        }
    }

    static func bankedText(_ seconds: TimeInterval) -> String {
        let m = max(1, Int((seconds / 60).rounded()))
        return m >= 60 ? String(format: "✓ %d:%02d h banked", m / 60, m % 60)
                       : "✓ \(m) min banked"
    }

    var pillSeconds: TimeInterval {
        switch Prefs.string(forKey: "pillDisplay") ?? "today" {
        case "session":
            return engine.accumulator.activeSeconds
        case "total":
            guard let p = selectedProject else { return 0 }
            return store.totalActiveSeconds(for: p) + engine.accumulator.activeSeconds
        default:
            return todaySeconds
        }
    }

    /// Today's seconds for any project (live-merged for the selected one).
    func todaySecondsFor(_ project: Project) -> TimeInterval {
        var s = store.activeSecondsToday(for: project)
        if project.persistentModelID == selectedProjectID {
            s += engine.accumulator.activeSeconds
        }
        return s
    }

    /// Daily rows with the live (not-yet-persisted) accumulator merged into
    /// today — keeps the Stats table consistent with the ring.
    func dayTotalsIncludingLive(for project: Project) -> [DayTotal] {
        var days = store.dayTotals(for: project)
        let live = engine.accumulator.activeSeconds
        guard project.persistentModelID == selectedProjectID, live > 0 else { return days }
        let today = Calendar.current.startOfDay(for: Date())
        if let i = days.firstIndex(where: { $0.day == today }) {
            days[i].activeSeconds += live
            days[i].lastEnd = Date()
        } else {
            days.insert(DayTotal(day: today, activeSeconds: live, sessionCount: 1,
                                 firstStart: engine.accumulator.sessionStart ?? Date(),
                                 lastEnd: Date()), at: 0)
        }
        return days
    }

    var detectLine: String {
        detector.resolveEdition() ?? "Resolve not running"
    }
}
