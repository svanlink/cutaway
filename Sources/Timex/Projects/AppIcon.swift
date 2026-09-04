import SwiftUI
import AppKit

/// The installed app's own icon, via the workspace. Nothing is bundled:
/// trademarks stay with their owners, and the icon is always the one the
/// user actually sees in their Dock.
@MainActor
enum AppIcon {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for app: InstalledApp?) -> NSImage? {
        guard let app else { return nil }
        let key = app.bundleID as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Icon tile: the real icon when installed, a dashed placeholder when not.
struct AppIconView: View {
    let app: InstalledApp?
    let name: String
    var size: CGFloat = 32

    var body: some View {
        if let image = AppIcon.image(for: app) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(DT.glyph)
                .foregroundStyle(DT.text3)
                .opacity(0.5)
                .frame(width: size, height: size)
                .help("\(name) is not installed")
                .accessibilityHidden(true)
        }
    }
}
