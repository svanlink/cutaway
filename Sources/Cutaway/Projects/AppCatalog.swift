import Foundation

/// The apps a video project is worked in, by suite. Pure data: names for
/// the picker, bundle-id PREFIXES for the engine (Adobe ids carry a year,
/// com.adobe.PremierePro.2025; prefix matching covers every version).
/// Icons are never shipped — InstalledApps finds the real one.
enum AppCatalog {
    struct Entry: Identifiable, Hashable, Sendable {
        let name: String
        let prefix: String
        var id: String { prefix }
    }

    struct Group: Identifiable, Sendable {
        let name: String
        let entries: [Entry]
        var id: String { name }
    }

    static let groups: [Group] = [
        // One tile: the prefix covers the free, Lite and Studio editions, and
        // only one of them is ever installed — three tiles showed two of
        // them as "not installed" on every Mac.
        Group(name: "DaVinci Resolve", entries: [
            Entry(name: "DaVinci Resolve", prefix: "com.blackmagic-design.DaVinciResolve"),
        ]),
        Group(name: "Adobe", entries: [
            Entry(name: "Premiere Pro", prefix: "com.adobe.PremierePro"),
            Entry(name: "After Effects", prefix: "com.adobe.AfterEffects"),
            Entry(name: "Photoshop", prefix: "com.adobe.Photoshop"),
            Entry(name: "Illustrator", prefix: "com.adobe.illustrator"),
            Entry(name: "Audition", prefix: "com.adobe.Audition"),
            Entry(name: "Lightroom Classic", prefix: "com.adobe.LightroomClassicCC"),
            Entry(name: "InDesign", prefix: "com.adobe.InDesign"),
            Entry(name: "Media Encoder", prefix: "com.adobe.ame.application"),
        ]),
        Group(name: "Microsoft Office", entries: [
            Entry(name: "Word", prefix: "com.microsoft.Word"),
            Entry(name: "Excel", prefix: "com.microsoft.Excel"),
            Entry(name: "PowerPoint", prefix: "com.microsoft.Powerpoint"),
            Entry(name: "Outlook", prefix: "com.microsoft.Outlook"),
            Entry(name: "OneNote", prefix: "com.microsoft.onenote.mac"),
        ]),
        Group(name: "Also", entries: [
            Entry(name: "Final Cut Pro", prefix: "com.apple.FinalCut"),
            Entry(name: "Motion", prefix: "com.apple.motionapp"),
            Entry(name: "Compressor", prefix: "com.apple.Compressor"),
            Entry(name: "Logic Pro", prefix: "com.apple.logic10"),
            Entry(name: "Blender", prefix: "org.blenderfoundation.blender"),
            Entry(name: "Affinity Photo", prefix: "com.seriflabs.affinityphoto"),
            Entry(name: "Affinity Designer", prefix: "com.seriflabs.affinitydesigner"),
            Entry(name: "Figma", prefix: "com.figma.Desktop"),
            Entry(name: "Notion", prefix: "notion.id"),
        ]),
    ]

    static let allEntries: [Entry] = groups.flatMap(\.entries)
}
