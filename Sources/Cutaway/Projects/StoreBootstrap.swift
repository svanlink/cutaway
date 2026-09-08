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
    static func newestCandidate(in backupsDir: URL, preferring preferredName: String?,
                                fm: FileManager = .default) -> Candidate? {
        guard let folder = StorePath.newestUsableBackup(in: backupsDir, preferring: preferredName, fm: fm),
              let store = StorePath.storeFile(in: folder, preferring: preferredName, fm: fm) else { return nil }
        return Candidate(folder: folder,
                         storeName: store.lastPathComponent,
                         sessions: StorePath.sessionCount(store))
    }
}
