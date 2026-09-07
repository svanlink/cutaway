import XCTest
@testable import Cutaway

/// The edit-day sheet used to read `model.selectedProject` at render time
/// while the target carried only a date. Detection auto-switches projects
/// when Resolve does, so a switch while the sheet was open kept project A's
/// prefilled figures on screen and saved them onto project B.
@MainActor
final class DayEditTargetTests: XCTestCase {

    func testTheTargetCarriesTheProjectItWasOpenedFor() throws {
        let store = try SessionStore(inMemory: true)
        let a = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        let b = try store.createProject(name: "Richemont", client: "", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        let target = DayEditTarget(day: Date(), project: a)
        XCTAssertIdentical(target.project, a)
        XCTAssertNotIdentical(target.project, b, "the sheet must not follow a project switch")
    }

    func testAddingATargetAlsoNamesItsProject() throws {
        let store = try SessionStore(inMemory: true)
        let a = try store.createProject(name: "Nyx", client: "", mode: .hourly,
                                        hourlyRate: 90, currency: .chf)
        let target = DayEditTarget(day: nil, project: a)
        XCTAssertNil(target.day, "nil day means Add")
        XCTAssertIdentical(target.project, a)
    }
}
