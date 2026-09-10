import SwiftUI

/// The way to an invoice, beside the way to a CSV. The CSV is still the
/// canonical hand-off for a bookkeeper; the PDF is what a client receives.
struct InvoiceButton: View {
    @Bindable var model: AppModel
    @State private var hovering = false
    @State private var sheetOpen = false

    /// Rendered by the toolbar rather than by us. A toolbar supplies its own
    /// background, border, hover and pressed states; a button that brings its
    /// own arrives as a pill sitting inside a well.
    var inToolbar = false

    var body: some View {
        if inToolbar {
            Button { model.showInvoiceSheet = true } label: {
                Label("Invoice…", systemImage: "doc.text")
            }
            .help("Create an invoice from tracked work")
            .disabled(model.selectedProject == nil)
            .accessibilityLabel("Create an invoice")
        } else {
            custom
        }
    }

    private var custom: some View {
        Button { sheetOpen = true } label: {
            HStack(spacing: DT.within) {
                Image(systemName: "doc.text").font(DT.buttonGlyph)
                Text("Invoice…").font(DT.small)
            }
            .foregroundStyle(hovering ? DT.text : DT.text2)
            .padding(.horizontal, 12)
            .padding(.vertical, DT.within)
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
