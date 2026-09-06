import XCTest
@testable import Cutaway

final class DiagnosticsTests: XCTestCase {
    func testPayloadsLandOnDiskNewestFirstAndAreBounded() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiagnosticsStore(directory: dir, keep: 3)
        for i in 1...5 {
            try store.write(Data("payload \(i)".utf8), stamp: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        let files = try store.reports()
        XCTAssertEqual(files.count, 3, "bounded")
        XCTAssertTrue(try String(contentsOf: files[0], encoding: .utf8).contains("payload 5"), "newest first")
        XCTAssertTrue(try store.combinedReport().contains("payload 3"))
    }
}
