import Foundation
import SwiftUI
import AppKit
import SwiftData

struct DayEditTarget: Identifiable {
    let id = UUID()
    /// nil = "Add time" for a day the app never saw.
    var day: Date?
    /// The project being corrected, captured when the sheet opens. Reading
    /// `selectedProject` instead let a Resolve project switch mid-edit save
    /// one project's figures onto another, silently.
    let project: Project
}

/// Glue between detection, persistence, and UI. One instance per app.
@Observable
@MainActor
final class AppModel {
    let engine: DetectionEngine
    let store: SessionStore
    let detector = ProjectDetector()
    /// Every store write reports here; the panel and Stats show its sentence.
    let storeErrors = StoreErrorReporter()

    /// Bumped when the user changes an accessibility display setting, purely
    /// to make SwiftUI re-render: the tokens are dynamic colours, and a
    /// dynamic colour only re-resolves when something redraws.
    private(set) var accessibilityDisplayGeneration = 0

    /// Anything else that wants to hear the engine's 1 Hz tick. The status
    /// item used to run a timer of its own for this; one clock is enough.
    var onEngineTick: (() -> Void)?
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
    var openPermissionsWindow: (() -> Void)?
    /// Last successful backup of the live store — launch, daily, quit or by hand.
    private(set) var lastBackup: Date? = Prefs.object(forKey: "lastBackupAt") as? Date
    /// Beside whatever store is actually open — NOT a hard path. A hard path
    /// meant a UI-test run (quarantined by CUTAWAY_DATA_DIR, but backed up by
    /// the real rule) wrote its throwaway store into the owner's real backups
    /// folder, where it competed with genuine backups for the rotation.
    static let backupsDir = StorePath.url().deletingLastPathComponent()
        .appendingPathComponent("Backups", isDirectory: true)
    /// True when SwiftData refused to open and we fell back to memory —
    /// the user must be TOLD their time won't survive a restart.
    var storeIsEphemeral = false
    enum StoreHeldBack: Error { case damaged }

    enum DamagedStoreChoice { case restore, revealBackups, continueWithout }

    /// Replaceable so the decision can be driven in a test or a scenario run.
    /// The default asks the owner, at launch, before anything is opened.
    nonisolated(unsafe) static var askAboutDamagedStore: (String, StoreBootstrap.Candidate?) -> DamagedStoreChoice = { reason, candidate in
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(localized: "Cutaway's billing data could not be read")
            if let candidate {
                let sessions = candidate.sessions.map { String($0) } ?? String(localized: "an unknown number of")
                alert.informativeText = String(localized: """
                    \(reason)

                    The newest backup Cutaway can read is \(candidate.stamp), holding \(sessions) work sessions.

                    Nothing has been changed yet. Restoring keeps the damaged file beside the restored one.
                    """)
                alert.addButton(withTitle: String(localized: "Restore That Backup"))
            } else {
                alert.informativeText = String(localized: """
                    \(reason)

                    Cutaway found no backup it can read. Nothing has been changed.
                    """)
            }
            alert.addButton(withTitle: String(localized: "Open Backups Folder"))
            alert.addButton(withTitle: String(localized: "Continue Without Restoring"))
            let clicked = alert.runModal()
            guard candidate != nil else {
                return clicked == .alertFirstButtonReturn ? .revealBackups : .continueWithout
            }
            switch clicked {
            case .alertFirstButtonReturn: return .restore
            case .alertSecondButtonReturn: return .revealBackups
            default: return .continueWithout
            }
        }
    }
    /// Installed apps, scanned once per launch for the icon rows. The
    /// picker scans again when opened, so a freshly installed app shows up
    /// there without a relaunch.
    private(set) var installedApps: [InstalledApp] = []

    /// Demo fixtures may only ever land in a quarantined store. Requesting
    /// demo mode without CUTAWAY_DATA_DIR is treated as the mistake it is.
    nonisolated static func demoSeedAllowed(demoRequested: Bool, dataDir: String?) -> Bool {
        demoRequested && dataDir != nil
    }

    init() {
        engine = ScenarioMode.isActive
            ? DetectionEngine(probes: ScenarioDriver.probes)
            : DetectionEngine()
        // Back up the real billing store before it opens (quiescent files).
        // Scenario/demo stores are disposable — never backed up.
        var launchBackupMade = false
        var holdBackStore = false
        if !ScenarioMode.isActive {
            // First launch after 1.3.1: bring the work over from the shared
            // default.store into Cutaway's own file (copied, never removed).
            do { if try StorePath.adoptLegacyIfNeeded() { NSLog("Cutaway: adopted the legacy default.store") } }
            catch { NSLog("Cutaway: legacy store adoption failed — %@", String(describing: error)) }
            let storeURL = StorePath.url()
            // A restore chosen in Settings is applied here, before anything opens.
            do { if try StorePath.applyPendingRestore(target: storeURL) { storeErrors.notice(String(localized: "The backup you chose has been restored.")) } }
            catch { NSLog("Cutaway: pending restore failed — %@", String(describing: error)) }
            // Litter from earlier restores and interrupted backups.
            StoreBackup.reapLitter(storeURL: storeURL, backupsDir: Self.backupsDir)

            // The page scan is O(file). After a clean quit there is nothing it
            // can find that the schema probe will not.
            let cleanShutdown = Prefs.bool(forKey: "cleanShutdown")
            Prefs.set(false, forKey: "cleanShutdown")
            switch StoreBootstrap.plan(storeURL: storeURL, backupsDir: Self.backupsDir,
                                       deepCheck: !cleanShutdown) {
            case .open:
                do {
                    if try StoreBackup.backUp(storeURL: storeURL, backupsDir: Self.backupsDir) != nil { launchBackupMade = true }
                } catch { NSLog("Cutaway: store backup skipped — %@", String(describing: error)) }
            case .openButWarn(let reason):
                // The disk, not the file. Back up nothing (a backup of an
                // unreadable store would only push good generations out of
                // rotation) and let SwiftData try — it usually succeeds, and
                // when it does not the in-memory fallback below says so.
                NSLog("Cutaway: store not readable right now — %@", reason)
                storeErrors.flag(String(localized: "read the billing store — \(reason). Nothing has been changed; try again after a restart."))
            case .askBeforeRestoring(let reason, let candidate):
                switch Self.askAboutDamagedStore(reason, candidate) {
                case .restore:
                    if let candidate {
                        do {
                            try StorePath.stagePendingRestore(from: candidate.folder, target: storeURL)
                            try StorePath.applyPendingRestore(target: storeURL)
                            storeErrors.notice(String(localized: "The backup \(candidate.stamp) has been restored. The damaged file is kept beside it."))
                        } catch {
                            NSLog("Cutaway: restore failed — %@", String(describing: error))
                            holdBackStore = true
                        }
                    }
                case .revealBackups:
                    NSWorkspace.shared.activateFileViewerSelecting([Self.backupsDir])
                    holdBackStore = true
                case .continueWithout:
                    // Never write over a damaged file: SwiftData would open it
                    // and recreate its tables, and the evidence would be gone.
                    holdBackStore = true
                }
            }
        }
        do {
            if holdBackStore { throw StoreHeldBack.damaged }
            store = try SessionStore()
        } catch {
            // SwiftData refusing to open is unrecoverable at runtime; an
            // in-memory store keeps the app alive for this run. Say why in
            // the log, and say so in the PANEL — a menu-bar user may never
            // open the Stats window where the ephemeral banner lives.
            store = try! SessionStore(inMemory: true)
            storeIsEphemeral = true
            if case StoreHeldBack.damaged = error {
                storeErrors.flag(String(localized: "use the billing store — it is damaged and was left untouched. Nothing tracked this run will be kept."))
            } else {
                NSLog("Cutaway: store failed to open, running in memory — %@", String(describing: error))
                storeErrors.flag("open the billing store — nothing tracked this run will be kept")
            }
        }
        projectsModel = ProjectsModel(store: store, engine: engine, errors: storeErrors)
        // After the last stored property: a closure over self before that is
        // a compile error, not a style choice.
        storeErrors.log = { [weak self] in self?.engine.logDetection("store", detail: $0) }
        if launchBackupMade { recordBackup() }
        // CUTAWAY_DEMO seeds sample data for screenshots and dev runs — but
        // ONLY into a quarantined store. On 2026-08-23 this guard did not
        // exist, `open` turned out to propagate the caller's environment
        // after all, and a screenshot launch seeded forty hours of fixtures
        // into the production billing store (which happened to be freshly
        // empty after an unrelated deletion). Real data came back from the
        // backups; the class of accident ends here: no harness convenience
        // may ever touch the store a user invoices from.
        if Self.demoSeedAllowed(demoRequested: ProcessInfo.processInfo.environment["CUTAWAY_DEMO"] != nil,
                                dataDir: ScenarioMode.dataDir),
           (try? store.projects())?.isEmpty == true {
            projectsModel.seedDemoData()
        }
        projectsModel.restoreSelection()
        if !ScenarioMode.isActive {
            engine.onResumePrompt = { [weak self] in self?.resumePromptOpen = true }
        }
        engine.onSessionClosed = { [weak self] record in
            guard let self, let project = self.selectedProject else { return false }
            let saved = self.storeErrors.attempt("save session") { try self.store.record(record, to: project) } != nil
            self.flashBankedSession(record.activeSeconds)
            return saved
        }
        engine.onManualPauseLifted = { [weak self] in self?.resumePromptOpen = false }
        // Crash recovery: persist the last checkpoint of a session that never
        // closed. The snapshot is cleared ONLY after a successful persist —
        // otherwise it survives for the next launch to retry.
        if let crashed = DetectionEngine.peekCrashedSession() {
            // Snapshots written before the project name was recorded fall
            // back to the selection; a named snapshot only ever lands on
            // that project — a phantom session on a new client is worse
            // than a dropped one, so an unmatched name is discarded, logged.
            let target: Project? = crashed.project.map { name in projects.first { ProjectName.matches($0.name, name) } }
                ?? selectedProject
            if let p = target {
                if storeErrors.attempt("recover the last session", { try store.record(crashed.record, to: p) }) != nil {
                    DetectionEngine.clearCrashedSessionSnapshot()
                }
            } else {
                // Kept, not cleared: the project may come back (rename, restore).
                engine.logDetection("recovery-deferred", detail: "project=\(crashed.project ?? "nil") not found")
            }
        }
        engine.projectNameForSnapshot = { [weak self] in self?.selectedProject?.name }
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
            // The app's ONE repeating timer. Ruled 2026-09-07: the backup
            // check rides this tick keyed on WALL-CLOCK time, never on a tick
            // count — a counter is meaningless under a variable cadence and
            // keeps counting across a sleep that wall time notices.
            if BackupPolicy.isDue(last: self.lastBackup, now: Date()) { self.backUpNow(reason: "daily") }
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
                let startedAt = self.projectsModel.intent.token
                let requestStarted = Date()
                Task { [weak self] in
                    let name = await self?.detector.detectViaScriptingAPI()
                    await MainActor.run {
                        tier1InFlight = false
                        guard let self else { return }
                        self.engine.logDetection("tier1",
                            detail: "name=\(name ?? "nil") took="
                                  + String(format: "%.2f", Date().timeIntervalSince(requestStarted)) + "s")
                        guard !self.projectsModel.intent.hasMovedSince(startedAt) else { return }
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
        // Same shape as the picker's scan: the detached task carries no
        // `self` across isolation, which Swift 6.0 (CI's Xcode 16) rejects.
        Task { @MainActor [weak self] in
            let apps = await Task.detached(priority: .utility) { InstalledApps.scan() }.value
            self?.installedApps = apps
        }
        if ScenarioMode.isActive {
            // The driver owns the tick loop and the virtual clock.
            ScenarioDriver.run(model: self)
        } else {
            engine.start()
        }
    }

    // MARK: - Backups of the running store

    /// A consistent snapshot of the live store. Returns whether one was written
    /// (nil from the snapshot means nothing changed since the last one).
    @discardableResult
    func backUpNow(reason: String) -> Bool {
        guard !ScenarioMode.isActive else { return false }
        do {
            let made = try StoreBackup.snapshot(storeURL: StorePath.url(), backupsDir: Self.backupsDir) != nil
            recordBackup()
            engine.logDetection("backup", detail: "reason=\(reason) wrote=\(made)")
            return made
        } catch {
            engine.logDetection("backup-failed", detail: "reason=\(reason) error=\(error)")
            return false
        }
    }

    private func recordBackup() {
        lastBackup = Date()
        Prefs.set(lastBackup, forKey: "lastBackupAt")
    }

    /// Quit: the engine flushes the open session, then the store is snapshotted.
    func prepareForTermination() {
        engine.stop()
        backUpNow(reason: "quit")
        Prefs.set(true, forKey: "cleanShutdown")
    }

    /// Scenario hook: same path as a Tier-1 detection.
    func scenarioDetect(_ name: String) {
        autoDetected(name, canCreate: true)
    }

    /// Detection moved attribution by itself — say so. A manual switch needs
    /// no announcement — the user is the one who just did it.
    private func autoDetected(_ name: String, canCreate: Bool) {
        if projectsModel.autoDetected(name, canCreate: canCreate), let now = selectedProject?.name {
            announce(Self.switchAnnouncement(to: now))
        }
    }

    /// Sets a day's TOTAL (what the Stats row shows). For today while
    /// recording, the running session is part of that total and keeps
    /// growing, so only the persisted part is adjusted to meet the target.
    /// False when the request could not be honoured (the running session
    /// alone is longer than the total asked for).
    @discardableResult
    func setDaySeconds(_ seconds: TimeInterval, on day: Date, for p: Project) -> Bool {
        // The running session only belongs to the SELECTED project's today;
        // detection may have switched projects while the sheet was open.
        let live = Calendar.current.isDateInToday(day) && p.persistentModelID == selectedProject?.persistentModelID
            ? engine.accumulator.activeSeconds : 0
        guard let target = Self.persistedTarget(requested: seconds, live: live) else { return false }
        return storeErrors.attempt("save the day edit") { try store.setActiveSeconds(target, on: day, for: p) } != nil
    }

    /// What the persisted part of today must become for the day to total
    /// `requested` with `live` seconds still running. Nil when impossible:
    /// clamping to zero used to delete every banked session of the day.
    nonisolated static func persistedTarget(requested: TimeInterval, live: TimeInterval) -> TimeInterval? {
        let t = requested - live
        return t < 0 ? nil : t
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

    // MARK: - Projects (forwarded — the views were written against AppModel)

    let projectsModel: ProjectsModel
    var selectedProjectID: PersistentIdentifier? { projectsModel.selectedProjectID }
    var selectedProject: Project? { projectsModel.selectedProject }
    var projects: [Project] { projectsModel.projects }
    func selectManually(_ p: Project) { projectsModel.selectManually(p) }
    func select(_ p: Project) { projectsModel.select(p) }
    func createProject(name: String, client: String, mode: BillingMode, rate: Double, budget: Double,
                       currency: BillingCurrency, apps: [String], isManual: Bool = false) {
        projectsModel.createProject(name: name, client: client, mode: mode, rate: rate, budget: budget,
                                    currency: currency, apps: apps, isManual: isManual)
    }
    func update(_ p: Project, name: String, client: String, mode: BillingMode, rate: Double,
                budget: Double, currency: BillingCurrency, apps: [String]) {
        projectsModel.update(p, name: name, client: client, mode: mode, rate: rate, budget: budget,
                             currency: currency, apps: apps)
    }
    func delete(_ p: Project, reassignTo t: Project?) { projectsModel.delete(p, reassignTo: t) }
    func applyAnchors() { projectsModel.applyAnchors() }
    static var globalWorkApps: [String] { ProjectsModel.globalWorkApps }
    static var defaultCurrency: BillingCurrency { ProjectsModel.defaultCurrency }
    static var defaultHourlyRate: Double { ProjectsModel.defaultHourlyRate }
    nonisolated static func clampedRate(_ r: Double) -> Double { ProjectsModel.clampedRate(r) }
    nonisolated static func isDuplicateName(_ n: String, existing: [String]) -> Bool {
        ProjectsModel.isDuplicateName(n, existing: existing)
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
        let duration = m >= 60 ? String(format: "%d:%02d h", m / 60, m % 60) : String(localized: "\(m) min")
        let when = calendar.isDate(end, inSameDayAs: now)
            ? end.formatted(.dateTime.hour().minute())
            : end.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return String(localized: "Last session: \(duration) · \(when)")
    }

    /// A session's wall-clock span, as the detail rows print it.
    static func sessionTimeRange(start: Date, end: Date) -> String {
        "\(start.formatted(.dateTime.hour().minute())) – \(end.formatted(.dateTime.hour().minute()))"
    }

    /// Today. Not a choice: three meanings for one glanced number destroys
    /// the glance — the pill stops being readable without remembering which
    /// mode it is in. The session total is in the panel, the project total in
    /// Stats, both one click away. (`pillDisplay` is left unread, as
    /// `dailyGoalHours` was.)
    var pillSeconds: TimeInterval { todaySeconds }

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
