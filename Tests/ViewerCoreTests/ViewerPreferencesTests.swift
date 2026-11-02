import XCTest
@testable import ViewerCore

final class ViewerPreferencesTests: XCTestCase {
    func testFreshPreferencesFitImagesAndIgnoreLegacyZoomFlag() throws {
        let suite = "ImageViewerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "fitToScreen")
        let preferences = ViewerPreferences(defaults: defaults)
        XCTAssertTrue(preferences.fitImagesToWindow)
        XCTAssertFalse(preferences.showImageInformation)
    }

    func testExplicitPreferencesSurviveReinitialization() throws {
        let suite = "ImageViewerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ViewerPreferences(defaults: defaults)
        original.fitImagesToWindow = false
        original.showImageInformation = true
        let restored = ViewerPreferences(defaults: defaults)
        XCTAssertFalse(restored.fitImagesToWindow)
        XCTAssertTrue(restored.showImageInformation)
        restored.fitImagesToWindow = true
        XCTAssertTrue(ViewerPreferences(defaults: defaults).fitImagesToWindow)
    }
}
