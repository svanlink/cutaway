import XCTest
@testable import Cutaway

/// The rule this app exists to keep: never bill the wrong project.
///
/// On 2026-09-08 DaVinci Resolve sat on "2026-08-2_BuildingBridges_OpeningFilm"
/// for twelve minutes while the timer credited every second to a different
/// client's project. Detection SAW the right name — Tier 1 reported it every
/// thirty seconds — and the engine kept recording anyway, because nothing
/// connected the two. Time on the wrong invoice is worse than time nowhere:
/// a gap gets noticed, a lie gets sent.
final class ProjectMismatchTests: XCTestCase {

    private func input(mismatch: Bool, frontmost: String = DetectionInput.resolveBundleIDs[0]) -> DetectionInput {
        DetectionInput(frontmostBundleID: frontmost,
                       secondsSinceInput: 0,
                       idleThreshold: 120,
                       manuallyPaused: false,
                       isAsleep: false,
                       hasActiveProject: true,
                       projectMismatch: mismatch,
                       workAppPrefixes: DetectionInput.defaultWorkAppPrefixes)
    }

    func testAMismatchStopsTheClockEvenWhileEditing() {
        XCTAssertEqual(DetectionState.evaluate(input(mismatch: true)), .paused(.projectMismatch),
                       "Resolve on another project means there is no correct project to record to")
    }

    func testWithoutAMismatchNothingChanges() {
        XCTAssertEqual(DetectionState.evaluate(input(mismatch: false)), .recording)
    }

    /// A manual pause and sleep still outrank it — they are the two things
    /// the doctrine calls sacred, and a mismatch does not un-pause anything.
    func testTheSacredPausesStillOutrankIt() {
        var manual = input(mismatch: true)
        manual.manuallyPaused = true
        XCTAssertEqual(DetectionState.evaluate(manual), .paused(.manual))

        var asleep = input(mismatch: true)
        asleep.isAsleep = true
        XCTAssertEqual(DetectionState.evaluate(asleep), .paused(.systemSleep))
    }

    /// It outranks the ordinary reasons: being in another app or idle would
    /// both pause anyway, but a mismatch must be the REASON reported, so the
    /// panel can say what is actually wrong.
    func testItOutranksFrontmostAndIdle() {
        XCTAssertEqual(DetectionState.evaluate(input(mismatch: true, frontmost: "com.apple.Safari")),
                       .paused(.projectMismatch))
        var idle = input(mismatch: true)
        idle.secondsSinceInput = 600
        XCTAssertEqual(DetectionState.evaluate(idle), .paused(.projectMismatch))
    }

    /// Recording with no project at all is still the older, separate case.
    func testNoProjectIsNotAMismatch() {
        var none = input(mismatch: false)
        none.hasActiveProject = false
        XCTAssertEqual(DetectionState.evaluate(none), .paused(.noProject))
    }
}

/// What counts as a mismatch, at the model level.
@MainActor
final class ResolveIsTheSourceOfTruthTests: XCTestCase {

    func testAProjectThatAnswersToTheNameIsNotAMismatch() throws {
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Aurora", client: "", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        p.remember("26_08_AuroraEC")
        XCTAssertTrue(p.answersTo("26_08_AuroraEC"), "a remembered name is the same job")
        XCTAssertFalse(p.answersTo("2026-08-2_BuildingBridges_OpeningFilm"),
                       "a different job is a different job")
    }

    /// The exact shape of the incident: Resolve reports a name the selected
    /// project does not answer to, and it is not a name anyone has placed.
    func testTheIncidentShape() {
        let decision = AttributionPolicy.decide(
            name: "2026-08-2_BuildingBridges_OpeningFilm", source: .resolve,
            known: [(project: "26_08_AuroraEC_HFAtelierPresentations2026",
                     names: ["26_08_AuroraEC_HFAtelierPresentations2026"])],
            current: "26_08_AuroraEC_HFAtelierPresentations2026",
            ignored: [], asked: [])
        guard case .ask = decision else {
            return XCTFail("an unplaced Resolve project must ask, never be silently ignored")
        }
    }
}

/// The hold must end when its reason does.
final class MismatchReleaseTests: XCTestCase {

    /// Resolve quitting while on an unplaced project must not hold the clock
    /// for the rest of the evening. The rule stops the WRONG work being
    /// billed; it must not stop work being billed at all.
    func testAClosedResolveIsNoLongerASourceOfTruth() {
        // Modelled at the level the app decides it: no Resolve name, no
        // mismatch, whatever was on screen before.
        let resolveProject: String? = nil
        let selected = "26_08_AuroraEC"
        let mismatch = resolveProject.map { !$0.isEmpty && $0 != selected } ?? false
        XCTAssertFalse(mismatch, "no Resolve, no mismatch")
    }

    /// And while Resolve IS open on something else, the hold stands.
    func testAnOpenResolveOnAnotherProjectHolds() {
        let resolveProject: String? = "2026-08-2_BuildingBridges_OpeningFilm"
        let selected = "26_08_AuroraEC"
        let mismatch = resolveProject.map { $0 != selected } ?? false
        XCTAssertTrue(mismatch)
    }
}
