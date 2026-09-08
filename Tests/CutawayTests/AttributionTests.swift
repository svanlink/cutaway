import XCTest
@testable import Cutaway

/// Where a newly seen name belongs.
///
/// The app used to decide this silently and get it wrong: on 2026-09-08 it
/// created "Untitled Project" and a second stray from Resolve project
/// switches, each holding minutes of real work attributed to nothing anyone
/// would invoice. Detection can see WHAT is open; only the owner knows what
/// job it is.
final class AttributionPolicyTests: XCTestCase {

    private let richemont = (project: "Richemont", names: ["Richemont", "Maisons_v03", "26_08_RichemontEC"])
    private let nyx = (project: "Nyx", names: ["Nyx"])

    func testAKnownNameSwitchesWithoutAsking() {
        let d = AttributionPolicy.decide(name: "Maisons_v03", source: .adobe(app: "After Effects"),
                                         known: [richemont, nyx], current: "Nyx",
                                         ignored: [], asked: [])
        XCTAssertEqual(d, .select(name: "Richemont"),
                       "answered once, remembered forever — that is the point")
    }

    func testTheNameOfTheProjectYouAreAlreadyOnIsSilent() {
        let d = AttributionPolicy.decide(name: "Richemont", source: .resolve,
                                         known: [richemont], current: "Richemont",
                                         ignored: [], asked: [])
        XCTAssertEqual(d, .stay, "no card, no announcement, nothing")
    }

    /// The case that caused the mess: an unknown name must ASK.
    func testAnUnknownNameAsksInsteadOfCreating() {
        let d = AttributionPolicy.decide(name: "Untitled Project", source: .resolve,
                                         known: [richemont], current: "Richemont",
                                         ignored: [], asked: [])
        XCTAssertEqual(d, .ask(name: "Untitled Project", source: .resolve, current: "Richemont"))
    }

    func testANameToldNotToTrackIsNeverAskedAboutAgain() {
        let d = AttributionPolicy.decide(name: "Holiday video", source: .resolve,
                                         known: [richemont], current: "Richemont",
                                         ignored: ["Holiday video"], asked: [])
        XCTAssertEqual(d, .ignore)
    }

    /// A card someone dismissed must not reappear on the next app switch.
    func testANameAlreadyAskedAboutThisRunIsNotAskedTwice() {
        let d = AttributionPolicy.decide(name: "Untitled Project", source: .resolve,
                                         known: [richemont], current: "Richemont",
                                         ignored: [], asked: ["Untitled Project"])
        XCTAssertEqual(d, .stay)
    }

    /// Tiers disagree about case and accents; two spellings of one job would
    /// split its billing.
    func testMatchingIgnoresCaseAndAccents() {
        let d = AttributionPolicy.decide(name: "maisons_V03", source: .adobe(app: "Photoshop"),
                                         known: [richemont], current: nil,
                                         ignored: [], asked: [])
        XCTAssertEqual(d, .select(name: "Richemont"))
    }

    func testAnEmptyNameIsNotAQuestion() {
        XCTAssertEqual(AttributionPolicy.decide(name: "   ", source: .resolve, known: [richemont],
                                                current: "Richemont", ignored: [], asked: []), .stay)
    }

    /// A document is asked about differently from a project.
    func testTheQuestionFitsWhereTheNameCameFrom() {
        let adobe = AttributionPolicy.question(name: "Maisons_v03", source: .adobe(app: "After Effects"),
                                               current: "Richemont")
        XCTAssertTrue(adobe.title.contains("After Effects"))
        XCTAssertTrue(adobe.line.contains("Richemont"), "offers the job you are already on")

        let resolve = AttributionPolicy.question(name: "Nyx Film", source: .resolve, current: nil)
        XCTAssertTrue(resolve.title.contains("Nyx Film"))
        XCTAssertTrue(resolve.line.contains("nothing is selected"))
    }
}

/// Three cards now; still never two at once.
final class ThreeCardArbiterTests: XCTestCase {

    private let ask = (name: "Untitled", source: AttributionPolicy.Source.resolve, current: "Richemont")

    func testAnIdleWarningOutranksAnAttributionQuestion() {
        let p = PromptArbiter.visible(idle: IdleWarning(secondsLeft: 20), resumeAsked: false,
                                      manuallyPaused: false, state: .recording, attribution: ask)
        XCTAssertEqual(p, .idle(secondsLeft: 20),
                       "a timer about to pause cannot wait; a question about attribution can")
    }

    func testAForgottenPauseOutranksItToo() {
        let p = PromptArbiter.visible(idle: nil, resumeAsked: true, manuallyPaused: true,
                                      state: .paused(.manual), attribution: ask)
        XCTAssertEqual(p, .resume, "a pause being worked through is costing money right now")
    }

    func testTheQuestionShowsWhenNothingElseIsAsking() {
        let p = PromptArbiter.visible(idle: nil, resumeAsked: false, manuallyPaused: false,
                                      state: .recording, attribution: ask)
        XCTAssertEqual(p, .attribution(name: "Untitled", source: .resolve, current: "Richemont"))
    }

    func testNoQuestionMeansNoCard() {
        XCTAssertNil(PromptArbiter.visible(idle: nil, resumeAsked: false, manuallyPaused: false,
                                           state: .recording, attribution: nil))
    }
}

/// Remembering, on the model.
@MainActor
final class ProjectNameMemoryTests: XCTestCase {

    func testAProjectAnswersToItsOwnNameAndToWhatItWasTold() throws {
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Richemont", client: "", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        XCTAssertTrue(p.answersTo("richemont"))
        XCTAssertFalse(p.answersTo("Maisons_v03"))

        p.remember("Maisons_v03")
        XCTAssertTrue(p.answersTo("Maisons_v03"))
        XCTAssertTrue(p.answersTo("maisons_v03"), "case is not a different job")
    }

    func testRememberingIsIdempotentAndIgnoresNoise() throws {
        let store = try SessionStore(inMemory: true)
        let p = try store.createProject(name: "Richemont", client: "", mode: .hourly,
                                        hourlyRate: 120, currency: .chf)
        p.remember("Maisons_v03")
        p.remember("Maisons_v03")
        p.remember("  ")
        p.remember("Richemont")
        XCTAssertEqual(p.detectedNames, ["Maisons_v03"],
                       "no duplicates, no blanks, and not its own name twice")
    }
}
