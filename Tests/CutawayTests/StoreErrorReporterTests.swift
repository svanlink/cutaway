import XCTest
@testable import Cutaway

/// A billing app that loses a save silently is not a billing app. Every
/// store write goes through here; a thrown error becomes a visible line.
@MainActor
final class StoreErrorReporterTests: XCTestCase {
    struct Boom: Error {}

    func testSuccessReturnsValueAndLeavesNoProblem() {
        let r = StoreErrorReporter()
        let v = r.attempt("save session") { 42 }
        XCTAssertEqual(v, 42)
        XCTAssertNil(r.problem)
    }

    func testFailureSurfacesWhatFailedAndLogsIt() {
        let r = StoreErrorReporter()
        var logged: [String] = []
        r.log = { logged.append($0) }
        let v: Int? = r.attempt("save session") { throw Boom() }
        XCTAssertNil(v)
        XCTAssertEqual(r.problem, "Couldn't save session. Your time since the last save is at risk — quit and relaunch Cutaway.")
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(logged[0].contains("save session"))
        r.clear()
        XCTAssertNil(r.problem)
    }
}
