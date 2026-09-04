import XCTest
@testable import Cutaway

final class AppIconRowTests: XCTestCase {
    func testUpToFourThenACount() {
        XCTAssertEqual(AppIconRowPolicy.shown(["a", "b"]).shown, ["a", "b"])
        XCTAssertEqual(AppIconRowPolicy.shown(["a", "b"]).more, 0)
        let six = AppIconRowPolicy.shown(["a", "b", "c", "d", "e", "f"])
        XCTAssertEqual(six.shown, ["a", "b", "c", "d"])
        XCTAssertEqual(six.more, 2)
    }

    func testEmptyListShowsNothing() {
        XCTAssertEqual(AppIconRowPolicy.shown([]).shown, [])
        XCTAssertEqual(AppIconRowPolicy.shown([]).more, 0)
    }
}
