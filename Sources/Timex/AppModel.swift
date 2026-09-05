import Foundation
import SwiftUI
import AppKit
import SwiftData

struct DayEditTarget: Identifiable {
    let id = UUID()
    /// nil = "Add time" for a day the app never saw.
    var day: Date?
}

/// Glue between detection, persistence, and UI. One instance per app.
@Observable
@MainActor
final class AppModel {
    let engine: DetectionEngine
    let store: SessionStore
    let detector = ProjectDetector()

    var selectedProjectID: PersistentIdentifier?
    /// Bumped when the user changes an accessibility display setting, purely
    /// to make SwiftUI re-render: the tokens are dynamic colours, and a
    /// dynamic colour only re-resolves when something redraws.
    private(set) var accessibilityDisplayGeneration = 0

    /// Anything else that wants to hear the engine's 1 Hz tick. The status
    /// item used to run a timer of its own for this; one clock is enough.
    var onEngineTick: (() -> Void)?
    /// Turns Resolve's steady state into transitions, so a manual switch is
    /// not overwritten by the next poll of a window that never moved.
    private var follower = DetectionFollower()
    /// Counts explicit choices, so an in-flight Tier-1 answer can tell
    /// whether the user moved on while it was running.
    private var intent = ManualIntent()
    var showNewProjectSheet = false
    /// Non-nil while the edit / delete sheet is up for that project.
    var editTarget: Project?
    var deleteTarget: Project?
    /// Non-nil while the day editor is up. `day == nil` = add a new day.
    var editDay: DayEditTarget?
    /// The ⌥⌘P registration failed (shortcut conflict) — surfaced in Settings.
    var hotkeyUnavailable = false
    /// Ask-mode: the engine asked "are you working?" and nobody has answered
    /// yet. The floating card shows while this is true and a manual pause
    /// is in force.
    var resumePromptOpen = false
    /// The user said "not now" to the Accessibility offer. Persisted: a
    /// permission prompt someone has already declined is nagware.
    var accessibilityOfferDismissed: Bool = Prefs.bool(forKey: "accessibilityOfferDismissed") {
        didSet { Prefs.set(accessibilityOfferDismissed, forKey: "accessibilityOfferDismissed") }
    }
    /// Captured from the main window's environment so AppKit surfaces
    /// (status-item panel) can reopen it.
    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    /// True when SwiftData refused to open and we fell back to memory —
    /// the user must be TOLD their time won't survive a restart.
    var storeIsEphemeral = false
    /// Installed apps, scanned once per launch for the icon rows. The
    /// picker scans again when opened, so a freshly installed app shows up
    /// there without a relaunch.
    private(set) var installedApps: [InstalledApp] = []

    /// Case/diacritic-insensitive duplicate check (mirrors switchOrCreate
    /// normalization) — two "Nyx film" projects is always a mistake.
    nonisolated static func isDuplicateName(_ name: String, existing: [String]) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        return existing.contains {
            $0.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Demo fixtures may only ever land in a quarantined store. Requesting
    /// demo mode without TIMEX_DATA_DIR is treated as the mistake it is.
    nonisolated static func demoSeedAllowed(demoRequested: Bool, dataDir: String?) -> Bool {
        demoRequested && dataDir != nil
    }

    /// Rates are money: never negative, and six figures an hour is a typo.
    nonisolated static func clampedRate(_ rate: Double) -> Double {
        min(max(0, rate), 99_999)
    }

    /// Money defaults live in ONE place. Three call sites used to answer this
    /// question differently — Settings, the New Project sheet, and
    /// auto-creation — which is how one Mac ended up creating projects two
    /// ways and invoicing in a currency nobody chose.
    static var defaultCurrency: TimexCurrency {
        if let raw = Prefs.string(forKey: "defaultCurrency"),
           let stored = TimexCurrency(rawValue: raw) { return stored }
        return TimexCurrency.fromLocale()
    }

    static var defaultHourlyRate: Double {
        clampedRate(Prefs.object(forKey: "defaultHourlyRate") as? Double ?? 85)
    }

    /// The Settings list — what a project with no list of its own uses, and
    /// what a new project starts with pre-ticked.
    static var globalWorkApps: [String] {
        AnchorSet.globalList(saved: Prefs.stringArray(forKey: "workApps"))
    }

    /// The ONLY writer of engine.workAppPrefixes. Called on launch, on every
    /// selection change, after a project edit, and after the Settings list
    /// changes — so a project-specific list is never overwritten by editing
    /// the global one, and a global edit still reaches projects that rely on it.
    func applyAnchors() {
        engine.workAppPrefixes = AnchorSet.resolve(project: selectedProject?.appBundleIDs ?? [],
                                                   global: Self.globalWorkApps)
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
            storeIsEphemeral = true
        }
        // TIMEX_DEMO seeds sample data for screenshots and dev runs — but
        // ONLY into a quarantined store. On 2026-08-23 this guard did not
        // exist, `open` turned out to propagate the caller's environment
        // after all, and a screenshot launch seeded forty hours of fixtures
        // into the production billing store (which happened to be freshly
        // empty after an unrelated deletion). Real data came back from the
        // backups; the class of accident ends here: no harness convenience
        // may ever touch the store a user invoices from.
        if Self.demoSeedAllowed(demoRequested: ProcessInfo.processInfo.environment["TIMEX_DEMO"] != nil,
                                dataDir: ScenarioMode.dataDir),
           (try? store.projects())?.isEmpty == true {
            seedDemoData()
        }
        // Restore last selected project by name (persistentModelID is not
        // stable across launches); fall back to the first project.
        let all = (try? store.projects()) ?? []
        let savedName = Prefs.string(forKey: "selectedProjectName")
        selectedProjectID = (all.first { $0.name == savedName } ?? all.first)?.persistentModelID
        engine.hasActiveProject = selectedProjectID != nil
        applyAnchors()
        if !ScenarioMode.isActive {
            engine.onResumePrompt = { [weak self] in self?.resumePromptOpen = true }
        }
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
            guard let self else { return }
            // Before the scenario guard: the pill is live during verification
            // runs too, and its width and label still have to keep up.
            self.onEngineTick?()
            guard !ScenarioMode.isActive else { return }
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
                self.autoDetected(detected, canCreate: false)
            }
            // Tier 1 fires fast the first time (tick 3) so a fresh install
            // picks up the open project within seconds. Steady-state interval:
            // spawning fuscript is the app's heaviest periodic cost, so when
            // the cheap Tier 2 (AX) is available it drops to every 120s.
            let tier1Interval = self.detector.accessibilityGranted ? 120 : 30
            if (tickCount == 3 || tickCount % tier1Interval == 0), !tier1InFlight {
                tier1InFlight = true
                // Stamped BEFORE the request: fuscript takes seconds, and an
                // answer about the world as it was must not overrule a choice
                // the user made since. (This guard was silently lost once in
                // an edit collision — the ManualIntent unit tests kept
                // passing because they test the struct, not the wiring. The
                // wiring is now pinned by DetectionWiringTests.)
                let startedAt = self.intent.token
                let requestStarted = Date()
                Task { [weak self] in
                    let name = await self?.detector.detectViaScriptingAPI()
                    await MainActor.run {
                        tier1InFlight = false
                        guard let self else { return }
                        self.engine.logDetection("tier1",
                            detail: "name=\(name ?? "nil") took="
                                  + String(format: "%.2f", Date().timeIntervalSince(requestStarted)) + "s")
                        guard !self.intent.hasMovedSince(startedAt) else { return }
                        // Tier 1 is the exact API name — it may create.
                        if let name { self.autoDetected(name, canCreate: true) }
                    }
                }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityDisplayGeneration += 1 }
        }
        Task.detached(priority: .utility) { [weak self] in
            let apps = InstalledApps.scan()
            await MainActor.run { self?.installedApps = apps }
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
        autoDetected(name, canCreate: true)
    }

    /// What Resolve just reported. Only a CHANGE moves attribution — polling
    /// the same project again is not new information, and treating it as new
    /// is what let a five-second timer overrule the user.
    private func autoDetected(_ name: String, canCreate: Bool) {
        guard let changed = follower.observe(name) else { return }
        let before = selectedProjectID
        switchOrCreate(changed, canCreate: canCreate)
        // Only when the app moved attribution by itself. A manual switch needs
        // no announcement — the user is the one who just did it.
        if selectedProjectID != before, let now = selectedProject?.name {
            announce(Self.switchAnnouncement(to: now))
        }
    }

    func update(_ project: Project, name newName: String, client: String, mode: BillingMode,
                rate: Double, budget: Double, currency: TimexCurrency, apps: [String]) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        try? store.update(project) {
            $0.name = name
            $0.client = client.trimmingCharacters(in: .whitespaces)
            $0.mode = mode
            $0.hourlyRate = Self.clampedRate(rate)
            $0.budget = max(0, budget)
            $0.currency = currency
            $0.appBundleIDs = DetectionInput.sanitizedPrefixes(apps)
        }
        if project.persistentModelID == selectedProjectID {
            Prefs.set(name, forKey: "selectedProjectName")
        }
        invalidateProjectCache()
        applyAnchors()
    }

    /// Sets a day's TOTAL (what the Stats row shows). For today while
    /// recording, the running session is part of that total and keeps
    /// growing, so only the persisted part is adjusted to meet the target.
    func setDaySeconds(_ seconds: TimeInterval, on day: Date) {
        guard let p = selectedProject else { return }
        var target = seconds
        if Calendar.current.isDateInToday(day) {
            target -= engine.accumulator.activeSeconds
        }
        try? store.setActiveSeconds(max(0, target), on: day, for: p)
    }

    /// Accepts "1:30", "1.5", "1,5", "90m" — whatever an editor types.
    nonisolated static func seconds(fromHoursText text: String) -> TimeInterval? {
        let t = text.lowercased()
            .replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "h", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.hasSuffix("m"), let m = Double(t.dropLast()) { return m >= 0 ? m * 60 : nil }
        if let colon = t.firstIndex(of: ":") {
            guard let h = Double(t[..<colon]), let m = Double(t[t.index(after: colon)...]),
                  h >= 0, (0..<60).contains(m) else { return nil }
            return h * 3600 + m * 60
        }
        guard let h = Double(t), h >= 0, h <= 24 * 366 else { return nil }
        return h * 3600
    }

    nonisolated static func hoursText(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
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
        if let match = projects.first(where: { ProjectName.matches($0.name, name) }) {
            if match.persistentModelID != selectedProjectID { select(match) }
            return
        }
        guard canCreate else { return }
        createProject(name: name, client: "", mode: .hourly,
                      rate: Self.defaultHourlyRate, budget: 0, currency: Self.defaultCurrency,
                      apps: Self.globalWorkApps)
    }

    /// The user picked this project. Explicit intent — it outranks any
    /// detection already in flight.
    func selectManually(_ project: Project) {
        intent.userChose()
        select(project)
    }

    func select(_ project: Project) {
        guard project.persistentModelID != selectedProjectID else { return }
        // Close the running span first so its time stays with the old project.
        engine.closeSessionNow(reason: "project-switch")
        selectedProjectID = project.persistentModelID
        engine.hasActiveProject = true
        Prefs.set(project.name, forKey: "selectedProjectName")
        applyAnchors()
    }

    func createProject(name: String, client: String, mode: BillingMode,
                       rate: Double, budget: Double, currency: TimexCurrency,
                       apps: [String], isManual: Bool = false) {
        guard let p = try? store.createProject(name: name, client: client, mode: mode,
                                               hourlyRate: rate, budget: budget, currency: currency,
                                               appBundleIDs: DetectionInput.sanitizedPrefixes(apps)) else { return }
        invalidateProjectCache()
        // Auto-creation routes here too, so only stamp intent when a human
        // filled in the sheet — `switchOrCreate` calls this as well.
        if isManual { intent.userChose() }
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
        let banked = store.dayTotals(for: p).first {
            Calendar.current.isDateInToday($0.day)
        }?.earned ?? 0
        let live = BillingEngine.earnings(activeSeconds: engine.accumulator.activeSeconds,
                                          hourlyRate: p.hourlyRate)
        return p.currency.format(banked + live)
    }


    /// What the menu-bar pill displays, per the "Menu bar shows" setting.
    /// Peak-end moment: a closed session is the billing event — the pill
    /// quietly confirms it for a few seconds instead of staying silent.
    var bankedFlash: String?

    func flashBankedSession(_ activeSeconds: TimeInterval) {
        guard activeSeconds >= 60 else { return }  // micro-sessions stay quiet
        let text = Self.bankedText(activeSeconds)
        bankedFlash = text
        announce(Self.bankedAnnouncement(activeSeconds))
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

    /// The durable receipt. The 4s banked flash is a peak-end moment, but it
    /// often fires after the editor already walked away — this line is still
    /// there when they come back and ask "did that block get counted?".
    var lastSessionLine: String? {
        guard let p = selectedProject, let s = store.lastSession(for: p) else { return nil }
        return Self.lastSessionText(activeSeconds: s.activeSeconds, end: s.end)
    }

    /// A receipt without its date lies the moment the day rolls over, so
    /// anything older than today carries its day.
    static func lastSessionText(activeSeconds: TimeInterval, end: Date,
                                now: Date = Date(), calendar: Calendar = .current) -> String {
        let m = max(1, Int((activeSeconds / 60).rounded()))
        let duration = m >= 60 ? String(format: "%d:%02d h", m / 60, m % 60) : "\(m) min"
        let when = calendar.isDate(end, inSameDayAs: now)
            ? end.formatted(.dateTime.hour().minute())
            : end.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "Last session: \(duration) · \(when)"
    }

    /// A session's wall-clock span, as the detail rows print it.
    static func sessionTimeRange(start: Date, end: Date) -> String {
        "\(start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))"
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
        // The open span has not been stamped yet, so it bills at the rate in
        // force right now — which is what it will be stamped with on close.
        let liveEarned = BillingEngine.earnings(activeSeconds: live, hourlyRate: project.hourlyRate)
        if let i = days.firstIndex(where: { $0.day == today }) {
            days[i].activeSeconds += live
            days[i].earned += liveEarned
            days[i].lastEnd = Date()
        } else {
            days.insert(DayTotal(day: today, activeSeconds: live, sessionCount: 1,
                                 firstStart: engine.accumulator.sessionStart ?? Date(),
                                 lastEnd: Date(), earned: liveEarned), at: 0)
        }
        return days
    }

    // MARK: - Spoken announcements

    /// The app reassigns which project is being billed on its own, from a
    /// window title it read five seconds ago. A sighted user sees the pill
    /// change; a VoiceOver user got nothing at all, and could bill hours to
    /// the wrong client without a single cue that anything had happened.
    ///
    /// Pure text, so what gets said is testable; posting is one line below.
    static func switchAnnouncement(to project: String) -> String {
        "Now tracking \(project)"
    }

    static func bankedAnnouncement(_ activeSeconds: TimeInterval) -> String {
        "Session saved, \(PillView.spokenDuration(activeSeconds))"
    }

    func announce(_ message: String) {
        guard !ScenarioMode.isActive else { return }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    // MARK: - Accessibility offer

    var shouldOfferAccessibility: Bool {
        // Verification runs must never be steered by onboarding UI — same
        // rule the first-run project sheet already follows.
        guard !ScenarioMode.isActive else { return false }
        return AccessibilityOfferPolicy.shouldOfferAccessibility(
            granted: detector.accessibilityGranted,
            dismissed: accessibilityOfferDismissed,
            hasProject: selectedProject != nil,
            zeroStateShowing: zeroState != nil
        )
    }

    /// Under five minutes left is when a warning is still actionable — enough
    /// to touch Resolve and keep the block alive, not so early it nags.
    static let researchWindowWarning: TimeInterval = 300

    var researchWindowIsClosing: Bool {
        guard case .satellite(let left) = engine.recordingSource else { return false }
        return left <= Self.researchWindowWarning
    }

    // MARK: - Zero state

    var zeroState: ZeroStatePolicy.ZeroState? {
        ZeroStatePolicy.zeroState(
            hasProject: selectedProject != nil,
            trackedSeconds: selectedProject.map { store.totalActiveSeconds(for: $0) } ?? 0,
            isRecording: engine.state == .recording,
            resolveRunning: detector.resolveEdition() != nil
        )
    }

    var detectLine: String {
        detector.resolveEdition() ?? "Resolve not running"
    }
}
