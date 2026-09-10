import Foundation
import Observation

/// One funnel for every store write. A thrown error becomes a visible
/// sentence in the panel and the Stats window, and a log line — never a
/// swallowed `try?`. Cleared by the next successful write.
@Observable
@MainActor
final class StoreErrorReporter {
    /// The last failed write — cleared by the next successful one.
    private(set) var problem: String?
    /// The store itself is unusable this run; no write can clear it.
    private(set) var fatal: String?
    /// What the panel and the Stats window show.
    var banner: String? { fatal ?? problem }
    /// Injected so tests can see the log line; the app wires the session logger.
    var log: (String) -> Void = { _ in }

    /// `recovery` adds the relaunch advice — right for a lost session, wrong
    /// for a failed project delete, where quitting would drop the open session.
    static func message(for what: String, recovery: Bool = true,
                        reason: String? = nil) -> String {
        // A stated reason replaces the relaunch advice: relaunching does not
        // void an invoice, and the sentence that names the remedy is the one
        // worth the space.
        if let reason, !reason.isEmpty {
            return String(localized: "Couldn't \(what). \(reason)")
        }
        return plain(for: what, recovery: recovery)
    }

    private static func plain(for what: String, recovery: Bool) -> String {
        // String(localized:), not a bare literal. The FRAGMENTS were in the
        // catalog and the sentence around them was not, so a German build
        // would have wrapped a translated verb phrase in an English frame.
        //
        // The fragments arrive without terminal punctuation — several already
        // ended in "." and produced "…will be kept.. Your time since…" — and
        // the recovery clause no longer repeats what the flag just said.
        recovery
            ? String(localized: "Couldn't \(what). Quit and relaunch Cutaway — time since the last save is at risk.")
            : String(localized: "Couldn't \(what).")
    }

    @discardableResult
    func attempt<T>(_ what: String, recovery: Bool = true, _ op: () throws -> T) -> T? {
        do {
            let v = try op()
            if problem != nil { problem = nil }
            return v
        } catch {
            // The reason, when the error has one written for a human.
            //
            // Every refusal in this app states its own cause — "That day is
            // on invoice INV-2026-0004. Void the invoice to change it.",
            // "This work is on invoice 2026-004." — and all of it was thrown
            // away here in favour of "Couldn't save the day edit.". The owner
            // was told an operation failed and never why, on the one class of
            // failure that has a specific remedy.
            problem = Self.message(for: what, recovery: recovery,
                                   reason: (error as? LocalizedError)?.errorDescription)
            log("store-error what=\(what) error=\(error)")
            return nil
        }
    }

    /// For failures outside a single write — the store refusing to open.
    func flag(_ what: String) { fatal = Self.message(for: what) }
    /// A fatal notice in the reporter's own words (a restore, not a failure).
    func notice(_ message: String) { fatal = message }

    func clear() { problem = nil }
}
