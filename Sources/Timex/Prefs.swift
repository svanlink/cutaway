import Foundation

/// All preference access goes through this handle. In scenario mode the app
/// uses an isolated suite so verification runs can NEVER touch the real
/// billing prefs (selected project, crash snapshots, thresholds).
/// UserDefaults is documented thread-safe; the nonisolated(unsafe) is for
/// the compiler, not a real hazard.
nonisolated(unsafe) let Prefs: UserDefaults = {
    if ProcessInfo.processInfo.environment["TIMEX_SCENARIO"] != nil {
        let suite = UserDefaults(suiteName: "com.vaneickelen.cutaway.scenario")!
        return suite
    }
    return .standard
}()

/// One-time migration from the app's earlier bundle id — the rename moved
/// the UserDefaults domain; settings and the crash snapshot come along.
enum PrefsMigration {
    static func migrateIfNeeded(into target: UserDefaults = Prefs) {
        guard !ScenarioMode.isActive,
              !target.bool(forKey: "didMigrateFromResolveTimer") else { return }
        let old = UserDefaults.standard.persistentDomain(forName: "com.vaneickelen.resolvetimer")
        migrate(from: old, into: target)
        target.set(true, forKey: "didMigrateFromResolveTimer")
    }

    /// Copies keys that don't already exist in the target. Split out so it
    /// is directly testable with plain dictionaries and scratch suites.
    static func migrate(from old: [String: Any]?, into target: UserDefaults) {
        guard let old else { return }
        for (key, value) in old where target.object(forKey: key) == nil {
            target.set(value, forKey: key)
        }
    }
}

enum ScenarioMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["TIMEX_SCENARIO"] != nil
    }
    static var scenarioPath: String? {
        ProcessInfo.processInfo.environment["TIMEX_SCENARIO"]
    }
    static var dataDir: String? {
        ProcessInfo.processInfo.environment["TIMEX_DATA_DIR"]
    }
}
