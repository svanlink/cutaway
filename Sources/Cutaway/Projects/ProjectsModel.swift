import Foundation
import SwiftData

/// Which project is being billed, and the ways that changes: the user picks
/// one, Resolve reports one, a sheet creates or edits or deletes one. Owns
/// the selection, the project caches, the manual-intent counter and the
/// anchor list the engine bills against. AppModel forwards the API the
/// views were written against.
@Observable
@MainActor
final class ProjectsModel {
    private let store: SessionStore
    private let engine: DetectionEngine
    private let errors: StoreErrorReporter

    var selectedProjectID: PersistentIdentifier?
    /// Turns Resolve's steady state into transitions, so a manual switch is
    /// not overwritten by the next poll of a window that never moved.
    private var follower = DetectionFollower()
    /// Counts explicit choices, so an in-flight Tier-1 answer can tell
    /// whether the user moved on while it was running. Read by AppModel's
    /// Tier-1 loop; only this class bumps it.
    private(set) var intent = ManualIntent()

    init(store: SessionStore, engine: DetectionEngine, errors: StoreErrorReporter) {
        self.store = store
        self.engine = engine
        self.errors = errors
    }

    // MARK: - Defaults and pure helpers

    /// Case/diacritic-insensitive duplicate check (mirrors switchOrCreate
    /// normalization) — two "Nyx film" projects is always a mistake.
    nonisolated static func isDuplicateName(_ name: String, existing: [String]) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        return existing.contains {
            $0.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// Rates are money: never negative, and six figures an hour is a typo.
    nonisolated static func clampedRate(_ rate: Double) -> Double {
        min(max(0, rate), 99_999)
    }

    /// Money defaults live in ONE place. Three call sites used to answer this
    /// question differently — Settings, the New Project sheet, and
    /// auto-creation — which is how one Mac ended up creating projects two
    /// ways and invoicing in a currency nobody chose.
    static var defaultCurrency: BillingCurrency {
        if let raw = Prefs.string(forKey: "defaultCurrency"),
           let stored = BillingCurrency(rawValue: raw) { return stored }
        return BillingCurrency.fromLocale()
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

    // MARK: - Launch

    /// Restore last selected project by name (persistentModelID is not
    /// stable across launches); fall back to the first project.
    func restoreSelection() {
        let all = (try? store.projects()) ?? []
        let savedName = Prefs.string(forKey: "selectedProjectName")
        selectedProjectID = (all.first { $0.name == savedName } ?? all.first)?.persistentModelID
        engine.hasActiveProject = selectedProjectID != nil
        applyAnchors()
    }

    func seedDemoData() {
        let cal = Calendar.current
        let resolve = DetectionInput.resolveBundleIDs[0]
        guard let nyx = try? store.createProject(name: "Nyx Fashion Film", client: "Nyx Studios",
                                                 mode: .hourly, hourlyRate: 85, currency: .chf,
                                                 appBundleIDs: [resolve, "com.adobe.PremierePro", "com.adobe.AfterEffects"]),
              let alpina = try? store.createProject(name: "Alpina Ski Promo", client: "Alpina Sports",
                                                    mode: .budget, hourlyRate: 85, budget: 4500, currency: .chf,
                                                    appBundleIDs: [resolve, "com.adobe.Photoshop", "com.adobe.illustrator"])
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
            try? store.record(rec, to: project)   // harness fixtures — not a user's data
        }
    }

    // MARK: - Reading

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

    // MARK: - Detection

    /// What Resolve just reported. Only a CHANGE moves attribution — polling
    /// the same project again is not new information, and treating it as new
    /// is what let a five-second timer overrule the user. Returns whether
    /// attribution moved, so the caller can say so out loud.
    @discardableResult
    func autoDetected(_ name: String, canCreate: Bool) -> Bool {
        guard let changed = follower.observe(name) else { return false }
        let before = selectedProjectID
        switchOrCreate(changed, canCreate: canCreate)
        return selectedProjectID != before
    }

    /// Switch attribution to the detected Resolve project — creating it (Tier 1
    /// only) with the default rate/currency if Cutaway has not seen it before.
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

    // MARK: - Choosing

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

    // MARK: - Creating, editing, deleting

    func createProject(name: String, client: String, mode: BillingMode,
                       rate: Double, budget: Double, currency: BillingCurrency,
                       apps: [String], isManual: Bool = false) {
        guard let p = errors.attempt("create the project", recovery: false, {
            try store.createProject(name: name, client: client, mode: mode,
                                    hourlyRate: rate, budget: budget, currency: currency,
                                    appBundleIDs: DetectionInput.sanitizedPrefixes(apps))
        }) else { return }
        invalidateProjectCache()
        // Auto-creation routes here too, so only stamp intent when a human
        // filled in the sheet — `switchOrCreate` calls this as well.
        if isManual { intent.userChose() }
        select(p)
        engine.hasActiveProject = true
    }

    func update(_ project: Project, name newName: String, client: String, mode: BillingMode,
                rate: Double, budget: Double, currency: BillingCurrency, apps: [String]) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Bank the open session BEFORE the rate moves. record() stamps the
        // rate at the moment a session closes, so a raise at 15:00 used to
        // reprice the whole day back to 09:00 — over-billing, and the exact
        // opposite of the sentence printed above the field: "Work already
        // recorded keeps the rate it was worked at." Only on a real change,
        // and only for the project actually being tracked.
        if Self.clampedRate(rate) != project.hourlyRate,
           project.persistentModelID == selectedProjectID {
            engine.bankOpenSession(reason: "rate-change")
        }
        errors.attempt("save the project", recovery: false) { try store.update(project) {
            $0.name = name
            $0.client = client.trimmingCharacters(in: .whitespaces)
            $0.mode = mode
            $0.hourlyRate = Self.clampedRate(rate)
            $0.budget = max(0, budget)
            $0.currency = currency
            $0.appBundleIDs = DetectionInput.sanitizedPrefixes(apps)
        } }
        if project.persistentModelID == selectedProjectID {
            Prefs.set(name, forKey: "selectedProjectName")
        }
        invalidateProjectCache()
        applyAnchors()
    }

    func delete(_ project: Project, reassignTo target: Project?) {
        let wasSelected = project.persistentModelID == selectedProjectID
        if wasSelected {
            // The open span belongs to the project being deleted (or its heir).
            engine.closeSessionNow(reason: "project-delete")
        }
        // Only move on if the delete actually happened. `store.delete` refuses
        // whenever sessions are invoiced and no heir was named — and the
        // selection used to move anyway, to `projects.first`, silently
        // retargeting every subsequent minute at whichever client was created
        // earliest. The only signal was a generic banner in another window.
        guard errors.attempt("delete the project", recovery: false,
                             { try store.delete(project, reassignTo: target) }) != nil else { return }
        invalidateProjectCache()
        if wasSelected {
            selectedProjectID = (target ?? projects.first)?.persistentModelID
            Prefs.set(selectedProject?.name, forKey: "selectedProjectName")
            engine.hasActiveProject = selectedProjectID != nil
        }
    }
}
