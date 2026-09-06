import XCTest
import SwiftUI
@testable import Cutaway

/// The panel is the app now. What it shows, in what order, is a pure
/// decision — pinned here so the zero state and the one-time Accessibility
/// offer cannot silently drop out of the surface a new user opens first.
@MainActor
final class PanelLayoutTests: XCTestCase {

    func testNoProjectShowsTheZeroStateInsteadOfTheProjectList() {
        let blocks = MenuBarPanel.blocks(zeroState: true, offersAccessibility: false,
                                         workDetectedWhilePaused: false, researchLabel: false, receipt: false)
        XCTAssertEqual(blocks, [.hero, .zeroState, .footer])
    }

    func testTheOfferSitsBetweenHeroAndProjects() {
        let blocks = MenuBarPanel.blocks(zeroState: false, offersAccessibility: true,
                                         workDetectedWhilePaused: false, researchLabel: false, receipt: true)
        XCTAssertEqual(blocks, [.hero, .accessibilityOffer, .projects, .receipt, .footer])
    }

    func testEverythingOnIsInTheEstablishedOrder() {
        let blocks = MenuBarPanel.blocks(zeroState: false, offersAccessibility: false,
                                         workDetectedWhilePaused: true, researchLabel: true, receipt: true)
        XCTAssertEqual(blocks, [.hero, .projects, .resumeBanner, .researchWindow, .receipt, .footer])
    }

    func testAFailedSaveOutranksEverythingButTheHero() {
        let blocks = MenuBarPanel.blocks(zeroState: false, offersAccessibility: false,
                                         workDetectedWhilePaused: false, researchLabel: false,
                                         receipt: false, storeProblem: true)
        XCTAssertEqual(blocks, [.hero, .storeProblem, .projects, .footer])
    }

    func testTheCardsRender() throws {
        let zero = ImageRenderer(content: ZeroStateCard(state: .noProject, createProject: {}).frame(width: 340))
        XCTAssertNotNil(zero.cgImage)
        let offer = ImageRenderer(content: AccessibilityOfferCard(enable: {}, dismiss: {}).frame(width: 340))
        XCTAssertNotNil(offer.cgImage)
    }
}
