import SwiftUI

/// The same tile picker the project sheet uses, bound to a global prefs list.
///
/// Replaced `AppListEditor` on 2026-09-08. That editor showed raw bundle-id
/// prefixes and asked the owner to type `com.adobe.PremierePro` by hand —
/// a second, uglier way to do what the icon picker already did well. The
/// picker's "Choose app…" panel is the escape hatch the typing field was.
struct AppPrefsPicker: View {
    let title: LocalizedStringKey
    let prefsKey: String
    let defaults: [String]
    let onChange: ([String]) -> Void

    @State private var selected: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            AppPickerView(selected: Binding(get: { Set(selected) },
                                            set: { save(Array($0)) }))
            Button("Reset to defaults") { save(defaults) }
                .buttonStyle(.link)
        }
        .padding(12)
        .frame(width: 380)
        .onAppear { selected = Prefs.stringArray(forKey: prefsKey) ?? defaults }
    }

    private func save(_ list: [String]) {
        let clean = DetectionInput.sanitizedPrefixes(list)
        selected = clean
        Prefs.set(clean, forKey: prefsKey)
        onChange(clean)
    }
}
