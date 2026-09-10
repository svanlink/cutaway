import SwiftUI

/// Title over a one-line explanation — the row label the native Forms use.
/// One definition: scripts/strings.py collects both literals from every call.
func labelled(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: DT.s1) {
        Text(title)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    // A control's label must be ONE element. Two stacked Texts gave the
    // pop-up buttons in Settings no description at all — the accessibility
    // audit had been red on exactly this since the native Forms landed.
    .accessibilityElement(children: .combine)
}
