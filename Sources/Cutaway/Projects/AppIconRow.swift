import SwiftUI

enum AppIconRowPolicy {
    /// At most `max` icons, then "+N". Order is the project's own.
    static func shown(_ prefixes: [String], max: Int = 4) -> (shown: [String], more: Int) {
        (Array(prefixes.prefix(max)), Swift.max(0, prefixes.count - max))
    }
}

/// Glanceable "what is this job": the project's app icons, small,
/// decorative — the row's label already names the project.
struct AppIconRow: View {
    let prefixes: [String]
    let installed: [InstalledApp]
    var size: CGFloat = 16

    var body: some View {
        // Real icons only: a prefix with no installed app draws nothing here.
        let s = AppIconRowPolicy.shown(prefixes.filter { InstalledApps.installed(matching: $0, in: installed) != nil })
        HStack(spacing: 3) {
            ForEach(s.shown, id: \.self) { prefix in
                AppIconView(app: InstalledApps.installed(matching: prefix, in: installed),
                            name: AppCatalog.allEntries.first { $0.prefix == prefix }?.name ?? prefix,
                            size: size)
            }
            if s.more > 0 {
                Text("+\(s.more)").font(DT.tag).foregroundStyle(DT.text3)
            }
        }
        .accessibilityHidden(true)
    }
}
