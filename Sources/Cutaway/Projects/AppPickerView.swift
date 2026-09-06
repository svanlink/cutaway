import SwiftUI

/// Selection + search, kept out of the view so it is testable.
struct AppPickerModel {
    var selected: Set<String>
    var query: String = ""

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Tiles only for apps on this Mac, with their real icons. An app that is
    /// not installed is not a choice here — "Choose app…" covers the rest.
    func visibleGroups(catalog: [AppCatalog.Group], installed: [InstalledApp]) -> [AppCatalog.Group] {
        catalog.compactMap { g in
            let hits = g.entries.filter { e in
                InstalledApps.installed(matching: e.prefix, in: installed) != nil
                    && (q.isEmpty || e.name.lowercased().contains(q) || e.prefix.lowercased().contains(q))
            }
            return hits.isEmpty ? nil : AppCatalog.Group(name: g.name, entries: hits)
        }
    }

    /// Installed apps the catalog does not already name.
    func otherApps(installed: [InstalledApp]) -> [InstalledApp] {
        installed.filter { app in
            !AppCatalog.allEntries.contains { app.bundleID.hasPrefix($0.prefix) }
                && (q.isEmpty || app.name.lowercased().contains(q) || app.bundleID.lowercased().contains(q))
        }
    }

    mutating func toggle(_ prefix: String) {
        if selected.contains(prefix) { selected.remove(prefix) } else { selected.insert(prefix) }
    }
}

/// Native grid of icon toggles by suite, a search field, and "Other…" for
/// everything installed that the catalog does not name.
struct AppPickerView: View {
    @Binding var selected: Set<String>
    @State private var query = ""
    @State private var installed: [InstalledApp] = []
    @State private var showOthers = false

    private var model: AppPickerModel { AppPickerModel(selected: selected, query: query) }
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search apps")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.visibleGroups(catalog: AppCatalog.groups, installed: installed)) { group in
                        Text(group.name.uppercased()).font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(group.entries) { entry in
                                tile(prefix: entry.prefix, name: entry.name,
                                     app: InstalledApps.installed(matching: entry.prefix, in: installed))
                            }
                        }
                    }
                    if model.visibleGroups(catalog: AppCatalog.groups, installed: installed).isEmpty, query.isEmpty {
                        Text("No editing apps found in /Applications — choose one below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Other…", isExpanded: $showOthers) {
                        let others = model.otherApps(installed: installed)
                        if others.isEmpty {
                            (query.isEmpty ? Text("Nothing else installed") : Text("No match"))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(others) { app in
                                    tile(prefix: app.bundleID, name: app.name, app: app)
                                }
                            }
                        }
                        // The scan looks in /Applications and ~/Applications, one
                        // vendor folder deep. An app anywhere else is still billable.
                        Button("Choose app…") { chooseApp() }
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 240)
        }
        .task {
            // One scan per sheet, off the main thread.
            let apps = await Task.detached(priority: .utility) { InstalledApps.scan() }.value
            installed = apps
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let app = InstalledApps.app(at: url) else { return }
        if !installed.contains(where: { $0.bundleID == app.bundleID }) { installed.append(app) }
        selected.insert(app.bundleID)
        showOthers = true
    }

    private func tile(prefix: String, name: String, app: InstalledApp?) -> some View {
        let on = selected.contains(prefix)
        return Button {
            var m = model; m.toggle(prefix); selected = m.selected
        } label: {
            VStack(spacing: 4) {
                AppIconView(app: app, name: name, size: 32)
                Text(name).font(.caption).foregroundStyle(on ? .primary : .secondary)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(on ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(on ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .help(app == nil ? "\(name) — not installed" : name)
        .accessibilityLabel(name)
        .accessibilityValue(on ? "selected" : "not selected")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
