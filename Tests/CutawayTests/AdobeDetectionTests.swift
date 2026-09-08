import XCTest
@testable import Cutaway

/// Adobe document names, testable on a machine with no Adobe installed —
/// which is every CI machine, and most days on this one.
final class AdobeDocumentTests: XCTestCase {

    func testTheFourAppsThatCanAnswer() {
        for id in ["com.adobe.Photoshop", "com.adobe.illustrator",
                   "com.adobe.InDesign", "com.adobe.AfterEffects"] {
            XCTAssertNotNil(AdobeDocument.app(forBundleID: id), "\(id) exposes its document")
        }
    }

    /// Bundle ids carry a year; the prefix must still match.
    func testAYearSuffixedBundleIDStillMatches() {
        XCTAssertEqual(AdobeDocument.app(forBundleID: "com.adobe.Photoshop.2026")?.displayName, "Photoshop")
    }

    /// Permanent, and pinned so a future pass has to argue with a test.
    func testPremiereNeverNamesADocument() {
        XCTAssertNil(AdobeDocument.app(forBundleID: "com.adobe.PremierePro.2026"),
                     "Premiere's dictionary is capture + editoriginal; the rest needs Screen Recording")
        XCTAssertFalse(AdobeDocument.namesDocuments("com.adobe.PremierePro"))
    }

    func testResolveIsNotAnAdobeApp() {
        XCTAssertFalse(AdobeDocument.namesDocuments("com.blackmagicdesign.resolve"))
    }

    /// The extension goes; nothing else does. Trimming version suffixes as
    /// well would merge two jobs that happen to share a stem.
    func testOnlyTheExtensionIsStripped() {
        XCTAssertEqual(AdobeDocument.projectCandidate(fromDocument: "Maisons_v03.psd"), "Maisons_v03")
        XCTAssertEqual(AdobeDocument.projectCandidate(fromDocument: "Richemont EC.aep"), "Richemont EC")
        XCTAssertEqual(AdobeDocument.projectCandidate(fromDocument: "no-extension"), "no-extension")
        XCTAssertNil(AdobeDocument.projectCandidate(fromDocument: "   "))
        XCTAssertNil(AdobeDocument.projectCandidate(fromDocument: ""))
    }

    /// Adobe app NAMES carry the year and change annually; ids do not.
    func testScriptsAddressAppsByIDNotName() {
        for app in AdobeDocument.supported {
            XCTAssertTrue(app.script.contains("application id"),
                          "\(app.displayName) would break every autumn addressed by name")
            XCTAssertFalse(app.script.contains("2026"))
        }
    }
}

@MainActor
final class AdobeDetectorTests: XCTestCase {

    private var logged: [(String, String)] = []

    private func detector() -> AdobeDetector {
        AdobeDetector(log: { [weak self] kind, detail in self?.logged.append((kind, detail)) })
    }

    override func tearDown() {
        AdobeDetector.runScript = { _ in .failure(.init(code: 0)) }
    }

    func testADocumentNameBecomesAProjectCandidate() {
        AdobeDetector.runScript = { _ in .success("Maisons_v03.psd") }
        XCTAssertEqual(detector().documentName(forBundleID: "com.adobe.Photoshop"),
                       .name("Maisons_v03"))
    }

    /// A permission dialog someone has already dismissed is nagware.
    func testADeclinedAppIsAskedExactlyOnce() {
        var calls = 0
        AdobeDetector.runScript = { _ in
            calls += 1
            return .failure(.init(code: AdobeDocument.notAuthorized))
        }
        let d = detector()
        XCTAssertEqual(d.documentName(forBundleID: "com.adobe.Photoshop"), .denied)
        XCTAssertEqual(d.documentName(forBundleID: "com.adobe.Photoshop"), .denied)
        XCTAssertEqual(calls, 1, "asked once, never again this run")
        XCTAssertEqual(logged.filter { $0.0 == "adobe-denied" }.count, 1)
    }

    /// Declining Photoshop must not silence Illustrator.
    func testDecliningOneAppDoesNotSilenceAnother() {
        AdobeDetector.runScript = { source in
            source.contains("Photoshop")
                ? .failure(.init(code: AdobeDocument.notAuthorized))
                : .success("Titles.ai")
        }
        let d = detector()
        XCTAssertEqual(d.documentName(forBundleID: "com.adobe.Photoshop"), .denied)
        XCTAssertEqual(d.documentName(forBundleID: "com.adobe.illustrator"), .name("Titles"))
    }

    /// No document open is an ordinary state, not a failure worth logging.
    func testNoDocumentOpenIsQuiet() {
        AdobeDetector.runScript = { _ in .failure(.init(code: AdobeDocument.noDocument)) }
        XCTAssertEqual(detector().documentName(forBundleID: "com.adobe.InDesign"), .nothing)
        XCTAssertTrue(logged.isEmpty, "an empty app is not an incident")
    }

    func testAnUnexpectedFailureIsLoggedButHarmless() {
        AdobeDetector.runScript = { _ in .failure(.init(code: -600)) }
        XCTAssertEqual(detector().documentName(forBundleID: "com.adobe.AfterEffects"), .nothing)
        XCTAssertEqual(logged.first?.0, "adobe-failed")
    }

    func testANonAdobeAppIsNeverScripted() {
        AdobeDetector.runScript = { _ in XCTFail("must not script a non-Adobe app"); return .success("") }
        XCTAssertEqual(detector().documentName(forBundleID: "com.blackmagicdesign.resolve"), .nothing)
    }
}
