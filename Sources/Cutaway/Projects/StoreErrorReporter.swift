import Foundation
import Observation

/// One funnel for every store write. A thrown error becomes a visible
/// sentence in the panel and the Stats window, and a log line — never a
/// swallowed `try?`. Cleared by the next successful write.
@Observable
@MainActor
final class StoreErrorReporter {
    private(set) var problem: String?
    /// Injected so tests can see the log line; the app wires the session logger.
    var log: (String) -> Void = { _ in }

    static func message(for what: String) -> String {
        "Couldn't \(what). Your time since the last save is at risk — quit and relaunch Cutaway."
    }

    @discardableResult
    func attempt<T>(_ what: String, _ op: () throws -> T) -> T? {
        do {
            let v = try op()
            if problem != nil { problem = nil }
            return v
        } catch {
            problem = Self.message(for: what)
            log("store-error what=\(what) error=\(error)")
            return nil
        }
    }

    func clear() { problem = nil }
}
