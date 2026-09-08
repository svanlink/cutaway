import Foundation

/// Reading the open document's name from the Adobe apps, so time spent in
/// them lands on the right project instead of merely counting.
///
/// Read on ACTIVATION only — never polled. Each app costs one Automation
/// prompt the first time, and the prompt is honest about what it buys: the
/// name of the open document, nothing else. Nothing here can create a
/// project: a document is called `Maisons_v03.psd`, which is a filename, and
/// letting filenames create projects would fill the switcher with versions
/// of the same job and split its billing.
///
/// Premiere Pro is absent on purpose and permanently. Its entire AppleScript
/// dictionary is `capture` and `editoriginal`; the only ways to its project
/// name are a CEP/UXP panel or Screen Recording, which this app refuses.
enum AdobeDocument {

    struct App: Equatable {
        /// Matches the bundle-id prefix the anchor list already uses.
        let prefix: String
        let displayName: String
        /// `application id` rather than a name: Adobe's app NAMES carry the
        /// year ("Adobe Photoshop 2026") and change annually; the ids do not.
        let script: String
    }

    static let supported: [App] = [
        App(prefix: "com.adobe.Photoshop", displayName: "Photoshop",
            script: #"tell application id "com.adobe.Photoshop" to get name of current document"#),
        App(prefix: "com.adobe.illustrator", displayName: "Illustrator",
            script: #"tell application id "com.adobe.illustrator" to get name of current document"#),
        App(prefix: "com.adobe.InDesign", displayName: "InDesign",
            script: #"tell application id "com.adobe.InDesign" to get name of active document"#),
        // After Effects exposes no document object; DoScript runs ExtendScript
        // and hands back what it evaluates to.
        App(prefix: "com.adobe.AfterEffects", displayName: "After Effects",
            script: #"tell application id "com.adobe.AfterEffects" to DoScript "app.project.file.name""#),
    ]

    static func app(forBundleID id: String) -> App? {
        supported.first { id.hasPrefix($0.prefix) }
    }

    /// Premiere is an anchor — its time counts — but it will never name a
    /// project. Pinned so a future pass does not quietly add it.
    static func namesDocuments(_ bundleID: String) -> Bool {
        app(forBundleID: bundleID) != nil
    }

    /// `Maisons_v03.psd` → `Maisons_v03`. Only the extension goes: trimming
    /// version suffixes as well would merge two jobs that share a stem.
    static func projectCandidate(fromDocument document: String) -> String? {
        let trimmed = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = (trimmed as NSString).deletingPathExtension
        return name.isEmpty ? nil : name
    }

    /// AppleScript's way of saying the user said no. Asked once, never nagged.
    static let notAuthorized = -1743
    /// No document open — an ordinary state, not a failure.
    static let noDocument = -1728
}
