import Foundation

/// Which apps prove work for the selected project.
///
/// A project's own list REPLACES the global one while it is selected — a
/// colour pass in Resolve must not land on an InDesign-only job's invoice.
/// An empty list means "the global list": that is what every project
/// created before the field existed says, and it is the fallback.
enum AnchorSet {
    static func resolve(project: [String], global: [String]) -> [String] {
        let own = DetectionInput.sanitizedPrefixes(project)
        return own.isEmpty ? global : own
    }

    /// The global list: what Settings saved, or the defaults. Resolve used
    /// to be an anchor outside this list, so a list saved before that
    /// changed has no Resolve entry — and would silently stop counting
    /// Resolve the day it became just another prefix. Put it back, once,
    /// at the front, unless something in the list already covers it.
    static func globalList(saved: [String]?) -> [String] {
        guard let saved else { return DetectionInput.defaultWorkAppPrefixes }
        let list = DetectionInput.sanitizedPrefixes(saved)
        let coversResolve = DetectionInput.resolveBundleIDs.allSatisfy { id in
            list.contains { id.hasPrefix($0) }
        }
        return coversResolve ? list : DetectionInput.sanitizedPrefixes(DetectionInput.resolveBundleIDs + list)
    }
}
