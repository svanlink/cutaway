import SwiftUI

/// Popover editor for a bundle-id prefix list (workflow anchors or
/// research satellites). Writes to Prefs and pushes into the engine live
/// via `onChange` — no relaunch needed. Native list; the picker in the
/// project sheet is the friendly way in, this is the escape hatch.
struct AppListEditor: View {
    let title: String
    let prefsKey: String
    let defaults: [String]
    let onChange: ([String]) -> Void

    @State private var prefixes: [String] = []
    @State private var newPrefix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text("Bundle id prefixes — e.g. com.adobe.PremierePro")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(prefixes, id: \.self) { p in
                    HStack {
                        Text(p).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { save(prefixes.filter { $0 != p }) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(p)")
                    }
                }
            }
            .frame(height: 200)
            HStack {
                TextField("com.example.app", text: $newPrefix)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bundle id prefix")
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newPrefix.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button("Reset to defaults") { save(defaults) }
                .buttonStyle(.link)
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { prefixes = Prefs.stringArray(forKey: prefsKey) ?? defaults }
    }

    private func add() {
        save(prefixes + [newPrefix])
        newPrefix = ""
    }

    private func save(_ list: [String]) {
        let clean = DetectionInput.sanitizedPrefixes(list)
        prefixes = clean
        Prefs.set(clean, forKey: prefsKey)
        onChange(clean)
    }
}
