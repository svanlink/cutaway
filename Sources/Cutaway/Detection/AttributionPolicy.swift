import Foundation

/// Where a newly seen name belongs — the decision Cutaway used to make
/// silently, and get wrong.
///
/// Until 2026-09-08 a project name Resolve reported and Cutaway had never
/// seen was created on the spot, with no question asked. That is how two
/// stray projects appeared in one afternoon — "Untitled Project" among them —
/// each with a few minutes of the owner's real time attached to the wrong
/// thing. Detection can see WHAT is open; only the owner knows what job it
/// belongs to, and asking once is cheaper than untangling it later.
enum AttributionPolicy {

    /// Where the name came from. It changes the question, not the logic:
    /// Resolve names a project, the Adobe apps name a document.
    enum Source: Equatable {
        case resolve
        case adobe(app: String)

        var isDocument: Bool { if case .adobe = self { return true }; return false }
    }

    enum Decision: Equatable {
        /// Known — switch and say nothing.
        case select(name: String)
        /// Already where it belongs.
        case stay
        /// Never ask about this one again.
        case ignore
        /// Ask the owner. Carries what is needed to word the question.
        case ask(name: String, source: Source, current: String?)
    }

    /// - Parameters:
    ///   - known: for each project, the names it answers to, in creation order.
    ///   - current: the selected project's name, if any.
    ///   - ignored: names the owner has said not to track.
    ///   - asked: names already asked about this run — a card that was
    ///     dismissed must not reappear on the next app switch.
    static func decide(name rawName: String, source: Source,
                       known: [(project: String, names: [String])],
                       current: String?,
                       ignored: [String],
                       asked: [String]) -> Decision {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .stay }
        if ignored.contains(where: { ProjectName.matches($0, name) }) { return .ignore }

        if let owner = known.first(where: { entry in
            entry.names.contains { ProjectName.matches($0, name) }
        }) {
            return owner.project == current ? .stay : .select(name: owner.project)
        }
        if asked.contains(where: { ProjectName.matches($0, name) }) { return .stay }
        return .ask(name: name, source: source, current: current)
    }

    /// The question, in the owner's terms. A document is asked about
    /// differently from a project: "is this the same job?" rather than
    /// "which job is this?".
    static func question(name: String, source: Source, current: String?) -> (title: String, line: String) {
        switch source {
        case .resolve:
            return (String(localized: "Track “\(name)”?"),
                    current.map { String(localized: "Resolve opened it. You are on \($0).") }
                        ?? String(localized: "Resolve opened it, and nothing is selected."))
        case .adobe(let app):
            return (String(localized: "\(app): “\(name)”"),
                    current.map { String(localized: "Is this part of \($0)?") }
                        ?? String(localized: "Which project is this?"))
        }
    }
}
