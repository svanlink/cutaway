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
                // Only if it actually happened. `restore` refuses a day that
                // has been invoiced SINCE the edit, and the announcement and
                // the redo registration used to run regardless — so VoiceOver
                // said "Undid Edit 4 September" over a day that had not
                // changed, and offered a redo of an undo that never occurred.
                guard model.storeErrors.attempt("undo the day edit", {
                    try model.store.restore(before, for: project)
                }) != nil else { return }
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
                // Two restores, two attempts. They shared one closure, so a
                // refusal on the target's day — that day invoiced since the
                // move — skipped the source's restore entirely and left the
                // session gone from the target AND absent from the source.
                // An undo that loses the work it was undoing.
                let targetOK = model.storeErrors.attempt("undo the move", {
                    try model.store.restore(beforeTarget, for: target)
                }) != nil
                let sourceOK = model.storeErrors.attempt("undo the move", {
                    try model.store.restore(beforeSource, for: source)
                }) != nil
                guard targetOK, sourceOK else { return }
                // And a redo, which this never registered: a move could be
                // undone once and never put back.
                model.reassignRedo(session: session, from: target, to: source,
                                   day: day, name: beforeSource.name)
                model.announce(String(localized: "Undid \(beforeSource.name)"))
            }
        }
    }

    /// The other half of the reassignment undo: put it back where it was
    /// sent. Registered from inside the undo so redo exists exactly as long
    /// as an undo has been performed.
    fileprivate func reassignRedo(session: WorkSession, from source: Project, to target: Project,
                                  day: Date, name: String) {
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                try? model.reassignSession(session, from: source, to: target)
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
