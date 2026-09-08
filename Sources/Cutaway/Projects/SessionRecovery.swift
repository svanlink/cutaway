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
        if storeErrors.attempt("recover the last session", { try store.record(record, to: project) }) != nil {
            DetectionEngine.clearCrashedSessionSnapshot()
        }
    }
}
