import SwiftUI
import AppKit

/// SwiftUI view → vector PDF, with no third-party anything.
///
/// `ImageRenderer.render` hands back a CGContext drawing closure, so the same
/// view that could be shown on screen writes itself into a PDF context. Text
/// stays selectable and the file stays small; a bitmap would be neither.
@MainActor
enum InvoicePDF {

    struct RenderError: LocalizedError {
        let what: String
        var errorDescription: String? { what }
    }

    /// One A4 page. ponytail: a month of daily lines fits; a period long
    /// enough to overflow needs pagination, and the guard below says so
    /// rather than silently cropping a client's invoice.
    static let maxLinesPerPage = 34
    /// A payment part takes the bottom 105 mm of the page — a third of it.
    static let maxLinesWithPaymentPart = 16

    @discardableResult
    static func write(_ invoice: Invoice, to url: URL) throws -> URL {
        let limit = invoice.creditorIBAN.isEmpty ? maxLinesPerPage : maxLinesWithPaymentPart
        guard invoice.orderedLines.count <= limit else {
            throw RenderError(what: String(localized: "This period has \(invoice.orderedLines.count) lines — more than one page holds alongside the payment part. Invoice a shorter period."))
        }
        let view = InvoiceDocumentView(invoice: invoice)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(InvoiceDocumentView.pageSize)

        var mediaBox = CGRect(origin: .zero, size: InvoiceDocumentView.pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfMetadata(invoice))
        else { throw RenderError(what: String(localized: "Could not create the PDF at that location.")) }

        var drew = false
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            drew = true
        }
        context.closePDF()
        guard drew else { throw RenderError(what: String(localized: "The invoice could not be drawn.")) }
        // A closure that ran is not a file that exists. On a full disk the
        // draw succeeds and the write does not, and the owner is left with a
        // locked invoice and a truncated PDF they believe is fine.
        let written = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let written, written > 1_000 else {
            throw RenderError(what: String(localized: "The PDF could not be written — check the disk and try saving it again from the invoice list."))
        }
        return url
    }

    private static func pdfMetadata(_ invoice: Invoice) -> CFDictionary {
        [kCGPDFContextTitle: invoice.number,
         kCGPDFContextAuthor: invoice.supplierBlock.split(separator: "\n").first.map(String.init) ?? "",
         kCGPDFContextCreator: "Cutaway"] as CFDictionary
    }

    /// The name a client should see on the file.
    static func filename(for invoice: Invoice) -> String {
        let client = invoice.clientBlock.split(separator: "\n").first.map(String.init) ?? ""
        let safe = client.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "\(invoice.number).pdf" : "\(invoice.number) \(safe).pdf"
    }
}
