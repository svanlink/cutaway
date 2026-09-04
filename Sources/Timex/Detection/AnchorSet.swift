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
}
