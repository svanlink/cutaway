import Foundation
import AppKit

/// The one modal the app raises at launch, and only when the billing store is
/// damaged. Presentation, kept out of the model: what it SAYS is the whole
/// feature, because the ruling is that nothing may be replaced without a yes.
enum DamagedStoreAlert {
    /// Everything the owner needs to choose rather than trust: the reason,
    /// the newest READABLE backup, its age and how many work sessions it
    /// holds — that count is how a real backup is told from a harness one.
    nonisolated(unsafe) static let ask: (String, StoreBootstrap.Candidate?) -> StoreBootstrap.DamagedStoreChoice = { reason, candidate in
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(localized: "Cutaway's billing data could not be read")
            if let candidate {
                let sessions = candidate.sessions.map { String($0) } ?? String(localized: "an unknown number of")
                alert.informativeText = String(localized: """
                    \(reason)

                    The newest backup Cutaway can read is \(candidate.stamp), holding \(sessions) work sessions.

                    Nothing has been changed yet. Restoring keeps the damaged file beside the restored one.
                    """)
                alert.addButton(withTitle: String(localized: "Restore That Backup"))
            } else {
                alert.informativeText = String(localized: """
                    \(reason)

                    Cutaway found no backup it can read. Nothing has been changed.
                    """)
            }
            alert.addButton(withTitle: String(localized: "Open Backups Folder"))
            alert.addButton(withTitle: String(localized: "Continue Without Restoring"))
            let clicked = alert.runModal()
            guard candidate != nil else {
                return clicked == .alertFirstButtonReturn ? .revealBackups : .continueWithout
            }
            switch clicked {
            case .alertFirstButtonReturn: return .restore
            case .alertSecondButtonReturn: return .revealBackups
            default: return .continueWithout
            }
        }
    }
}
