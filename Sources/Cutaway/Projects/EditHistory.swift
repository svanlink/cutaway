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
