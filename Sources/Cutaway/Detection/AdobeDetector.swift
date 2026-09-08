import Foundation
import AppKit

/// Runs the document-name script for an Adobe app when it comes forward.
///
/// The script execution is injected, so the matching and the refusal
/// handling are testable on a machine with no Adobe installed — which is
/// every CI machine, and most days on this one.
@MainActor
final class AdobeDetector {

    enum Outcome: Equatable {
        case name(String)
        /// The owner declined Automation for this app. Asked once.
        case denied
        /// No document open, app busy, script failed — all ordinary.
        case nothing
    }

    /// AppleScript reports failure as a number; `Result` wants an `Error`.
    struct ScriptError: Error, Equatable { let code: Int }

    /// Replaced in tests. Returns the script's string result, or an error code.
    nonisolated(unsafe) static var runScript: (String) -> Result<String, ScriptError> = { source in
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(ScriptError(code: 0)) }
        let result = script.executeAndReturnError(&error)
        if let error {
            return .failure(ScriptError(code: error[NSAppleScript.errorNumber] as? Int ?? 0))
        }
        return .success(result.stringValue ?? "")
    }

    /// Apps whose Automation prompt was declined. Not retried this run: a
    /// permission dialog someone has already dismissed is nagware.
    private var declined: Set<String> = []
    private let log: (String, String) -> Void

    init(log: @escaping (String, String) -> Void) { self.log = log }

    func documentName(forBundleID bundleID: String) -> Outcome {
        guard let app = AdobeDocument.app(forBundleID: bundleID) else { return .nothing }
        guard !declined.contains(app.prefix) else { return .denied }

        switch Self.runScript(app.script) {
        case .success(let raw):
            guard let candidate = AdobeDocument.projectCandidate(fromDocument: raw) else { return .nothing }
            log("adobe", "app=\(app.displayName) document=\(raw)")
            return .name(candidate)
        case .failure(let error) where error.code == AdobeDocument.notAuthorized:
            declined.insert(app.prefix)
            log("adobe-denied", "app=\(app.displayName) — asked once, not again this run")
            return .denied
        case .failure(let error):
            // No document open is the common one and is not worth a line.
            if error.code != AdobeDocument.noDocument {
                log("adobe-failed", "app=\(app.displayName) code=\(error.code)")
            }
            return .nothing
        }
    }
}
