import Foundation
import SwiftData

/// Everything needed to put a day back exactly as it was.
///
/// A day edit that SHRINKS a day trims sessions newest-first and deletes any
/// that reach zero — real recorded work, gone, with no way back. That was
/// acceptable while the day total was the only editable thing; it is not
/// acceptable as the app grows more editing surfaces, and it is why undo
/// lands before any of them.
struct DayEdit: Sendable {
    struct Session: Sendable {
        let start: Date
        let end: Date
        let activeSeconds: TimeInterval
        let hourlyRate: Double
        let isAdjusted: Bool
        /// Carried, or an undo silently unlocks work an invoice claims and
        /// leaves that invoice's provenance pointing at sessions that no
        /// longer exist.
        let uid: String
        let invoiceNumber: String
    }

    let day: Date
    let sessions: [Session]
    /// What the user did, in their words — "Edit 4 September", for the menu.
    let name: String
}

@MainActor
extension AppModel {
    // MARK: - Undo

    static func dayEditName(_ day: Date) -> String {
        String(localized: "Edit \(day.formatted(.dateTime.day().month(.wide)))")
    }

    func registerUndo(of before: DayEdit, for project: Project) {
        undoManager.setActionName(before.name)
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                // Snapshot the CURRENT state first so undo can be redone.
                let after = model.store.dayEdit(before.day, for: project, named: before.name)
                model.storeErrors.attempt("undo the day edit") {
                    try model.store.restore(before, for: project)
                }
                model.registerUndo(of: after, for: project)
                model.announce(String(localized: "Undid \(before.name)"))
            }
        }
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    func undoLastEdit() { undoManager.undo() }

    // MARK: - Session spans

    /// Every span edit goes through here so it is undoable and so the day's
    /// previous shape is captured before anything is destroyed.
    func addSession(from start: Date, to end: Date, to project: Project) throws {
        let before = store.dayEdit(start, for: project, named: Self.dayEditName(start))
        try store.addSession(from: start, to: end, for: project)
        registerUndo(of: before, for: project)
    }

    func editSession(_ session: WorkSession, from start: Date, to end: Date, in project: Project) throws {
        let before = store.dayEdit(session.start, for: project, named: Self.dayEditName(session.start))
        try store.updateSession(session, from: start, to: end)
        registerUndo(of: before, for: project)
    }

    func splitSession(_ session: WorkSession, at moment: Date, in project: Project) throws {
        let before = store.dayEdit(session.start, for: project, named: Self.dayEditName(session.start))
        try store.splitSession(session, at: moment)
        registerUndo(of: before, for: project)
    }

    /// Reassignment touches TWO days' worth of history — the source day in
    /// the old project and the same day in the new one — so both are captured.
    func reassignSession(_ session: WorkSession, from source: Project, to target: Project) throws {
        let day = session.start
        let beforeSource = store.dayEdit(day, for: source, named: Self.dayEditName(day))
        let beforeTarget = store.dayEdit(day, for: target, named: Self.dayEditName(day))
        try store.reassign(session, to: target)
        undoManager.setActionName(beforeSource.name)
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.storeErrors.attempt("undo the move") {
                    try model.store.restore(beforeTarget, for: target)
                    try model.store.restore(beforeSource, for: source)
                }
            }
        }
    }

    func deleteSession(_ session: WorkSession, in project: Project) throws {
        let before = store.dayEdit(session.start, for: project, named: Self.dayEditName(session.start))
        try store.deleteSession(session)
        registerUndo(of: before, for: project)
    }
    func redoLastEdit() { undoManager.redo() }

    /// What the persisted part of today must become for the day to total
    /// `requested` with `live` seconds still running. Nil when impossible:
    /// clamping to zero used to delete every banked session of the day.
}
