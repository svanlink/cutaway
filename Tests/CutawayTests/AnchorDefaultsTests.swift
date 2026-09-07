import XCTest
@testable import Cutaway

/// The picker's catalog and the default anchor list drifted apart: InDesign
/// was offered in the picker but was not an anchor, so it was never pre-ticked
/// on a new project and every InDesign hour was tracked as nothing.
final class AnchorDefaultsTests: XCTestCase {

    private var defaults: [String] { DetectionInput.defaultWorkAppPrefixes }

    func testTheDeliveryChainIsAnchoredByDefault() {
        for id in ["com.adobe.AfterEffects", "com.adobe.Photoshop", "com.adobe.PremierePro",
                   "com.adobe.illustrator", "com.adobe.Audition", "com.adobe.InDesign"] {
            XCTAssertTrue(defaults.contains(id), "\(id) must count toward a project out of the box")
        }
    }

    /// Deliberate exclusions — pinned so a future "add every Adobe app" pass
    /// has to argue with a test instead of a comment.
    func testUnattendedAndOffChainAppsAreNotAnchors() {
        XCTAssertFalse(defaults.contains { $0.hasPrefix("com.adobe.ame") },
                       "Media Encoder renders unattended")
        XCTAssertFalse(defaults.contains { $0.lowercased().contains("lightroom") },
                       "Lightroom is not in this editor's delivery chain")
    }

    /// Every default anchor is a real bundle-id prefix, not a display name.
    func testDefaultsAreBundleIDPrefixes() {
        for id in defaults {
            XCTAssertTrue(id.contains("."), "\(id) does not look like a bundle id")
            XCTAssertFalse(id.hasSuffix("."), "\(id) has a trailing dot")
        }
    }
}
