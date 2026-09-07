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
    static func message(for what: String, recovery: Bool = true) -> String {
        recovery
            ? "Couldn't \(what). Your time since the last save is at risk — quit and relaunch Cutaway."
            : "Couldn't \(what)."
    }

    @discardableResult
    func attempt<T>(_ what: String, recovery: Bool = true, _ op: () throws -> T) -> T? {
        do {
            let v = try op()
            if problem != nil { problem = nil }
            return v
        } catch {
            problem = Self.message(for: what, recovery: recovery)
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
