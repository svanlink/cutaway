import Foundation

/// All preference access goes through this handle. In scenario mode the app
/// uses an isolated suite so verification runs can NEVER touch the real
/// billing prefs (selected project, crash snapshots, thresholds).
/// UserDefaults is documented thread-safe; the nonisolated(unsafe) is for
/// the compiler, not a real hazard.
nonisolated(unsafe) let Prefs: UserDefaults = {
    let env = ProcessInfo.processInfo.environment
    if let suite = PrefsPolicy.suiteName(scenario: env["CUTAWAY_SCENARIO"] != nil,
                                         dataDir: env["CUTAWAY_DATA_DIR"]) {
        return UserDefaults(suiteName: suite)!
    }
    return .standard
}()

enum PrefsPolicy {
    /// A quarantined store means quarantined prefs: a demo/capture launch with
    /// CUTAWAY_DATA_DIR once wrote its selected project and "primer shown"
    /// into the user's real defaults, so the real first run never showed it.
    static func suiteName(scenario: Bool, dataDir: String?) -> String? {
        if scenario { return "com.vaneickelen.cutaway.scenario" }
        if dataDir != nil { return "com.vaneickelen.cutaway.harness" }
        return nil
    }
}

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
        ProcessInfo.processInfo.environment["CUTAWAY_SCENARIO"] != nil
    }
    static var scenarioPath: String? {
        ProcessInfo.processInfo.environment["CUTAWAY_SCENARIO"]
    }
    static var dataDir: String? {
        ProcessInfo.processInfo.environment["CUTAWAY_DATA_DIR"]
    }
}
