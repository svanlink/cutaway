import Foundation

/// A session that never closed, from a launch that never quit.
///
/// The decision here is which project it belongs to, and it is a decision
/// worth testing: a phantom session on the wrong client is worse than a
/// dropped one, so a snapshot naming a project that no longer exists is
/// KEPT rather than guessed at — the project may come back by a rename or a
/// restore, and the snapshot is only cleared once it is safely persisted.
enum SessionRecovery {

    enum Target: Equatable {
        /// Write it here.
        case project(String)
        /// The snapshot predates project names; use whatever is selected.
        case selection
        /// Named a project that is not here. Keep the snapshot, log, move on.
        case defer_(String)
    }

    /// Pure: given the snapshot's project name and the projects that exist,
    /// where does this session go?
    static func target(snapshotProject: String?, existing: [String]) -> Target {
        guard let name = snapshotProject else { return .selection }
        if let match = existing.first(where: { ProjectName.matches($0, name) }) {
            return .project(match)
        }
        return .defer_(name)
    }
}

extension AppModel {
    /// A session that never closed, from a launch that never quit. The
    /// snapshot is cleared ONLY after a successful persist — otherwise it
    /// survives for the next launch to retry.
    /// Replays anything the store refused on an earlier run.
    ///
    /// Runs BEFORE crash recovery: both write sessions, and the journal
    /// holds the older work. A record is dropped only once its own save has
    /// returned, so a still-full volume simply leaves it for next time.
    func replayUnsavedSessions() {
        let pending = unsaved.pending()
        guard !pending.isEmpty else { return }
        let projects = (try? store.projects()) ?? []
        var stillUnsaved: [UnsavedSessions.Entry] = []
        for entry in pending {
            // Whose work it is, not whose turn it is. This used to write every
            // parked record to `selectedProject` — whatever happened to be
            // chosen at launch — so an auto-switch or a rename in between
            // billed another client. A name nobody answers to is HELD, which
            // is the ruling `target(snapshotProject:existing:)` already makes
            // twenty lines above for the crash snapshot.
            guard let project = UnsavedSessions.owner(of: entry, among: projects) else {
                stillUnsaved.append(entry)
                continue
            }
            let saved = storeErrors.attempt("save session") {
                // uid makes a replay idempotent: save() can throw after the
                // row has landed, so this record may already be stored.
                try store.record(entry.record, to: project,
                                 uid: entry.uid, rate: entry.hourlyRate)
            } != nil
            if !saved { stillUnsaved.append(entry) }
        }
        if !unsaved.replace(with: stillUnsaved) {
            // A journal that cannot be rewritten replays the same hours on
            // every launch, forever, and used to do it silently.
            storeErrors.flag(String(localized: "clear the record of unsaved work"))
        }
    }

    func recoverCrashedSession() {
        guard let crashed = DetectionEngine.peekCrashedSession() else { return }
        switch SessionRecovery.target(snapshotProject: crashed.project,
                                      existing: projects.map(\.name)) {
        case .project(let name):
            guard let p = projects.first(where: { $0.name == name }) else { return }
            persistRecovered(crashed.record, to: p)
        case .selection:
            guard let p = selectedProject else { return }
            persistRecovered(crashed.record, to: p)
        case .defer_(let name):
            // Kept, not cleared: the project may come back (rename, restore).
            engine.logDetection("recovery-deferred", detail: "project=\(name) not found")
        }
    }

    func persistRecovered(_ record: SessionRecord, to project: Project) {
        // Derived from the session's own start, so it is the SAME identity on
        // every relaunch. The snapshot is deliberately kept when a persist
        // fails, and `save()` can throw with the row already on disk — so
        // without a stable uid the retry inserted the crashed session a
        // second time and billed it twice. Two sessions cannot start in the
        // same second on one clock, so the start is identity enough.
        //
        // If the first attempt landed a shorter checkpoint than the final
        // snapshot, the retry now skips instead of topping it up. That
        // under-bills by the last few seconds, which is the direction this
        // app resolves toward — unlike billing the whole session twice.
        let uid = "crash-\(Int(record.start.timeIntervalSinceReferenceDate))"
        if storeErrors.attempt("recover the last session",
                               { try store.record(record, to: project, uid: uid) }) != nil {
            DetectionEngine.clearCrashedSessionSnapshot()
        }
    }
}
