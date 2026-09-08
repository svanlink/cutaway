import SwiftUI

/// The way to an invoice, beside the way to a CSV. The CSV is still the
/// canonical hand-off for a bookkeeper; the PDF is what a client receives.
struct InvoiceButton: View {
    @Bindable var model: AppModel
    @State private var hovering = false
    @State private var sheetOpen = false

    var body: some View {
        Button { sheetOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(DT.buttonGlyph)
                Text("Invoice…").font(DT.small)
            }
            .foregroundStyle(hovering ? DT.text : DT.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DT.card2, in: RoundedRectangle(cornerRadius: DT.rMd))
            .overlay(RoundedRectangle(cornerRadius: DT.rMd)
                .stroke(hovering ? DT.signal.opacity(0.5) : DT.strokeSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .disabled(model.selectedProject == nil)
        .accessibilityLabel("Create an invoice")
        .sheet(isPresented: $sheetOpen) {
            if let p = model.selectedProject {
                InvoiceSheet(model: model, project: p)
            }
        }
    }
}
