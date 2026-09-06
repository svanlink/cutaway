import XCTest
@testable import Cutaway

final class PrefsPolicyTests: XCTestCase {
    func testAQuarantinedStoreMeansQuarantinedPrefs() {
        XCTAssertNil(PrefsPolicy.suiteName(scenario: false, dataDir: nil), "a real launch uses the real defaults")
        XCTAssertEqual(PrefsPolicy.suiteName(scenario: true, dataDir: nil), "com.vaneickelen.cutaway.scenario")
        XCTAssertEqual(PrefsPolicy.suiteName(scenario: false, dataDir: "/tmp/x"), "com.vaneickelen.cutaway.harness")
        XCTAssertEqual(PrefsPolicy.suiteName(scenario: true, dataDir: "/tmp/x"), "com.vaneickelen.cutaway.scenario")
    }
}
