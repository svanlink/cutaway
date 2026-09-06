import SwiftUI

/// Title over a one-line explanation — the row label the native Forms use.
/// One definition: scripts/strings.py collects both literals from every call.
func labelled(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
