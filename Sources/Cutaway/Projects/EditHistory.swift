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
    func redoLastEdit() { undoManager.redo() }

    /// What the persisted part of today must become for the day to total
    /// `requested` with `live` seconds still running. Nil when impossible:
    /// clamping to zero used to delete every banked session of the day.
}
