import Foundation

/// What to do about the billing store, decided BEFORE anything opens it.
///
/// Ruled 2026-09-07: the app may never move, replace or overwrite the live
/// store without the owner saying yes first — no exception, including the
/// automatic path. The classifier can be wrong, `.replaced-<stamp>` is not a
/// visible undo, and every recovery that has actually worked on this Mac was
/// done by hand. So this type only ever DECIDES; it never touches a file.
enum StoreBootstrap {

    /// A backup offered to the owner, described in the terms they can judge:
    /// when it was taken, what the store inside is called, and how many work
    /// sessions it holds — that count is how a real backup is told apart from
    /// one a test run left behind.
    struct Candidate: Equatable {
        let folder: URL
        let storeName: String
        let sessions: Int?

        var stamp: String { folder.lastPathComponent }
    }

    enum Plan: Equatable {
        /// Absent (first run) or usable. Open it, say nothing.
        case open
        /// The DISK said no — a permission bit, a full volume, a Time Machine
        /// lock. Touch nothing: it heals, and a restore does not give back the
        /// minutes it drops.
        case openButWarn(reason: String)
        /// The FILE said no. Ask; never act.
        case askBeforeRestoring(reason: String, candidate: Candidate?)
    }

    static func plan(storeURL: URL, backupsDir: URL, deepCheck: Bool = true,
                     fm: FileManager = .default) -> Plan {
        switch StorePath.verdict(storeURL, deepCheck: deepCheck) {
        case .absent, .usable:
            return .open
        case .unreadable(let reason):
            return .openButWarn(reason: reason)
        case .damaged(let reason):
            return .askBeforeRestoring(reason: reason,
                                       candidate: newestCandidate(in: backupsDir,
                                                                  preferring: storeURL.lastPathComponent,
                                                                  fm: fm))
        }
    }

    /// Newest backup whose store is actually usable — torn, foreign and empty
    /// ones are skipped rather than offered.
    // MARK: - Acting on the plan

    enum DamagedStoreChoice { case restore, revealBackups, continueWithout }

    /// What opening the store produced. Messages are RETURNED rather than
    /// posted: this runs before AppModel finishes initialising, and a banner
    /// is the caller's business anyway.
    struct Opened {
        let store: SessionStore
        let isEphemeral: Bool
        let backupMade: Bool
        var notices: [String] = []
        var flags: [String] = []
    }

    private enum HeldBack: Error { case damaged }

    /// The launch sequence, out of `AppModel.init`.
    ///
    /// It lived there for a year and grew to about seventy-five lines of the
    /// only code in the app that irreversibly touches the billing store —
    /// untestable in place, because testing it meant launching the app. The
    /// decision closures (`ask`, `reveal`) keep AppKit out and let a test
    /// drive every branch.
    @MainActor
    static func open(scenario: Bool = ScenarioMode.isActive,
                     storeURL: URL = StorePath.url(),
                     backupsDir: URL,
                     ask: (String, Candidate?) -> DamagedStoreChoice,
                     reveal: (URL) -> Void,
                     adoptLegacy: () throws -> Bool = { try StorePath.adoptLegacyIfNeeded() },
                     makeStore: () throws -> SessionStore = { try SessionStore() },
                     makeMemoryStore: () throws -> SessionStore = { try SessionStore(inMemory: true) }
    ) -> Opened {
        var notices: [String] = []
        var flags: [String] = []
        var backupMade = false
        var holdBack = false

        // Scenario and demo stores are disposable — never adopted, never
        // backed up, never restored.
        if !scenario {
            do { if try adoptLegacy() { NSLog("Cutaway: adopted the legacy default.store") } }
            catch { NSLog("Cutaway: legacy store adoption failed — %@", String(describing: error)) }
            do {
                if try StorePath.applyPendingRestore(target: storeURL) {
                    notices.append(String(localized: "The backup you chose has been restored."))
                }
            } catch {
                NSLog("Cutaway: pending restore failed — %@", String(describing: error))
                // applyPendingRestore moves the live store aside first and
                // the chosen backup into place second. A throw between those
                // two leaves NO file at billing.store — and `plan` then reads
                // .absent, which is a legitimate first run, so SwiftData
                // creates a fresh empty database and the owner tracks a full
                // day into it believing everything was eaten. Refuse instead:
                // the damaged path already runs in memory behind a red
                // banner, which is exactly right for a restore that is
                // half done.
                holdBack = true
                flags.append(String(localized: "finish restoring the backup you chose — the store was left as it is. Nothing tracked this run will be kept."))
            }
            StoreBackup.reapLitter(storeURL: storeURL, backupsDir: backupsDir)

            // Always deep. The old comment claimed a clean quit left nothing
            // for the page scan to find that the schema probe would not —
            // which is false: quick_check finds page-level corruption, the
            // schema probe finds a missing table, and page corruption between
            // a clean quit and the next launch is precisely what a Time
            // Machine restore or a bad sector produces. Undetected, every
            // backup generation becomes a copy of the corrupt store. The
            // justification was cost, on a file that is 94 KB.
            Prefs.set(false, forKey: "cleanShutdown")
            switch plan(storeURL: storeURL, backupsDir: backupsDir, deepCheck: true) {
            case .open:
                do {
                    if try StoreBackup.backUp(storeURL: storeURL, backupsDir: backupsDir) != nil { backupMade = true }
                } catch { NSLog("Cutaway: store backup skipped — %@", String(describing: error)) }
            case .openButWarn(let reason):
                // The disk, not the file. Back up nothing — a backup of an
                // unreadable store would only push good generations out of
                // rotation — and let SwiftData try, which usually works.
                NSLog("Cutaway: store not readable right now — %@", reason)
                flags.append(String(localized: "read the billing store — \(reason). Nothing has been changed; try again after a restart."))
            case .askBeforeRestoring(let reason, let candidate):
                switch ask(reason, candidate) {
                case .restore:
                    if let candidate {
                        do {
                            try StorePath.stagePendingRestore(from: candidate.folder, target: storeURL)
                            try StorePath.applyPendingRestore(target: storeURL)
                            notices.append(String(localized: "The backup \(candidate.stamp) has been restored. The damaged file is kept beside it."))
                        } catch {
                            NSLog("Cutaway: restore failed — %@", String(describing: error))
                            holdBack = true
                        }
                    }
                case .revealBackups:
                    reveal(backupsDir)
                    holdBack = true
                case .continueWithout:
                    // Never write over a damaged file: SwiftData would open it
                    // and recreate its tables, and the evidence would be gone.
                    holdBack = true
                }
            }
        }

        do {
            if holdBack { throw HeldBack.damaged }
            return Opened(store: try makeStore(), isEphemeral: false, backupMade: backupMade,
                          notices: notices, flags: flags)
        } catch {
            // Unrecoverable at runtime; an in-memory store keeps the app
            // alive for this run. Say so in the PANEL — a menu-bar user may
            // never open the window where the ephemeral banner lives.
            if case HeldBack.damaged = error {
                flags.append(String(localized: "use the billing store — it is damaged and was left untouched. Nothing tracked this run will be kept."))
            } else {
                NSLog("Cutaway: store failed to open, running in memory — %@", String(describing: error))
                flags.append(String(localized: "open the billing store — nothing tracked this run will be kept"))
            }
            // A failure here would mean no store at all; the in-memory one
            // cannot realistically fail, and crashing is honest if it does.
            return Opened(store: try! makeMemoryStore(), isEphemeral: true, backupMade: backupMade,
                          notices: notices, flags: flags)
        }
    }

    static func newestCandidate(in backupsDir: URL, preferring preferredName: String?,
                                fm: FileManager = .default) -> Candidate? {
        guard let folder = StorePath.newestUsableBackup(in: backupsDir, preferring: preferredName, fm: fm),
              let store = StorePath.storeFile(in: folder, preferring: preferredName, fm: fm) else { return nil }
        return Candidate(folder: folder,
                         storeName: store.lastPathComponent,
                         sessions: StorePath.sessionCount(store))
    }
}
