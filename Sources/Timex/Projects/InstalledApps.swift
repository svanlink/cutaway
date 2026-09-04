import AppKit

struct InstalledApp: Identifiable, Hashable, Sendable {
    let name: String
    let bundleID: String
    let url: URL
    var id: String { bundleID }
}

/// What is actually on this Mac. One scan per sheet open, off the main
/// thread; the result answers both "Other…" and "is this catalog app
/// installed, and where is its icon".
enum InstalledApps {
    static let defaultDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    static func scan(directories: [URL] = defaultDirectories) -> [InstalledApp] {
        let fm = FileManager.default
        var found: [String: InstalledApp] = [:]
        for dir in directories {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = dict["CFBundleIdentifier"] as? String, !id.isEmpty else { continue }
                let name = (dict["CFBundleDisplayName"] as? String)
                    ?? (dict["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                // First hit wins: /Applications outranks ~/Applications.
                if found[id] == nil { found[id] = InstalledApp(name: name, bundleID: id, url: url) }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed bundle a catalog PREFIX stands for, if any.
    static func installed(matching prefix: String, in apps: [InstalledApp]) -> InstalledApp? {
        apps.first { $0.bundleID.hasPrefix(prefix) }
    }
}
