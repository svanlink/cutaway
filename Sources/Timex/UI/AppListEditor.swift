import SwiftUI

/// Popover editor for a bundle-id prefix list (workflow anchors or
/// research satellites). Writes to Prefs and pushes into the engine
/// live via `onChange` — no relaunch needed.
struct AppListEditor: View {
    let title: String
    let prefsKey: String
    let defaults: [String]
    let onChange: ([String]) -> Void

    @State private var prefixes: [String] = []
    @State private var newPrefix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DT.s2) {
            Text(title).font(DT.smallSemibold).foregroundStyle(DT.text)
            Text("Bundle id prefixes — e.g. com.adobe.PremierePro")
                .font(DT.captionMedium).foregroundStyle(DT.text3)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(prefixes, id: \.self) { p in
                        HStack {
                            Text(p).font(DT.small).foregroundStyle(DT.text2)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                save(prefixes.filter { $0 != p })
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(DT.text3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(p)")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(DT.card2, in: RoundedRectangle(cornerRadius: DT.rMd))
                    }
                }
            }
            .frame(maxHeight: 220)

            HStack(spacing: DT.s2) {
                TextField("com.example.app", text: $newPrefix)
                    .textFieldStyle(.roundedBorder)
                    .font(DT.small)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newPrefix.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button("Reset to defaults") { save(defaults) }
                .font(DT.captionMedium)
                .buttonStyle(.plain)
                .foregroundStyle(DT.orange)
        }
        .padding(DT.s3)
        .frame(width: 320)
        .onAppear {
            prefixes = Prefs.stringArray(forKey: prefsKey) ?? defaults
        }
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
