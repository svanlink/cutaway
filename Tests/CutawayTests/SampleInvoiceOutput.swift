import XCTest
import SwiftData
@testable import Cutaway

/// Writes a realistic invoice to CUTAWAY_SAMPLE_PDF when that is set, so a
/// human can look at the page. Skipped otherwise.
@MainActor
final class SampleInvoiceOutput: XCTestCase {
    func testWriteSample() throws {
        guard let path = ProcessInfo.processInfo.environment["CUTAWAY_SAMPLE_PDF"] else {
            throw XCTSkip("set CUTAWAY_SAMPLE_PDF to write a sample")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Maisons Presentation 2026", client: "Richemont EC",
                                        mode: .hourly, hourlyRate: 120, currency: .chf)
        p.clientAddress = "Route des Biches 10\n1752 Villars-sur-Glâne"
        p.clientVATNumber = "CHE-116.281.710"

        func day(_ d: Int, _ h: Int, hours: Double, adjusted: Bool = false) throws {
            let start = cal.date(from: DateComponents(year: 2026, month: 8, day: d, hour: h))!
            try store.record(SessionRecord(start: start,
                                           end: start.addingTimeInterval(hours * 3600),
                                           activeSeconds: hours * 3600),
                             to: p, calendar: cal)
        }
        try day(2, 9, hours: 3.1)
        try day(3, 10, hours: 5.2)
        try day(4, 9, hours: 6.9)
        try day(5, 14, hours: 4.6)
        // One day corrected by hand — the trace has to reach the page.
        let corrected = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12))!
        try store.setActiveSeconds(2 * 3600, on: corrected, for: p, calendar: cal)

        let from = cal.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let to = cal.date(from: DateComponents(year: 2026, month: 9, day: 30))!
        let invoice = try store.issueInvoice(
            for: p, from: from, to: to, taxMode: .swissVAT,
            supplier: "Sebastian van Eickelen\nBadenerstrasse 12\n8004 Zürich",
            supplierVATNumber: "CHE-123.456.789",
            clientBlock: p.clientBlock,
            iban: "CH93 0076 2011 6238 5295 7",
            now: cal.date(from: DateComponents(year: 2026, month: 9, day: 8))!,
            calendar: cal)
        try InvoicePDF.write(invoice, to: URL(fileURLWithPath: path))
    }
}
