import SwiftUI
import AppKit

struct CSVExportButton: View {
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        Button(action: export) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .bold))
                Text("Export CSV").font(DT.small)
            }
            .foregroundStyle(hovering ? DT.text : DT.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DT.card2, in: RoundedRectangle(cornerRadius: DT.rMd))
            .overlay(
                RoundedRectangle(cornerRadius: DT.rMd)
                    .stroke(hovering ? DT.orange.opacity(0.4) : DT.strokeSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(model.selectedProject == nil)
        .accessibilityLabel("Export project data as CSV")
    }

    private func export() {
        guard let p = model.selectedProject else { return }
        // Live seconds included so the file always matches the screen.
        let csv = CSVExporter.export(
            project: p.name, client: p.client, mode: p.mode,
            currency: p.currency, hourlyRate: p.hourlyRate, budget: p.budget,
            days: model.dayTotalsIncludingLive(for: p)
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(p.name) — Cutaway.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csv.data(using: .utf8)?.write(to: url)
            } catch {
                // A silent export failure in a billing app is unacceptable.
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
