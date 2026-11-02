import Foundation

public final class ViewerPreferences {
    private let defaults: UserDefaults
    // New names deliberately ignore the old fitToScreen flag, which earlier
    // builds also wrote during temporary zoom gestures.
    private let fitKey = "viewer.fitImagesToWindow"
    private let infoKey = "viewer.showImageInformation"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [fitKey: true, infoKey: false])
    }

    public var galleryThumbnailSize: Double {
        get { let value = defaults.double(forKey: "viewer.galleryThumbnailSize"); return value == 0 ? 200 : min(340, max(130, value)) }
        set { defaults.set(min(340, max(130, newValue)), forKey: "viewer.galleryThumbnailSize") }
    }
    public var slideshowInterval: Double {
        get { let value = defaults.double(forKey: "viewer.slideshowInterval"); return value == 0 ? 3 : min(60, max(1, value)) }
        set { defaults.set(min(60, max(1, newValue)), forKey: "viewer.slideshowInterval") }
    }

    public var fitImagesToWindow: Bool {
        get { defaults.bool(forKey: fitKey) }
        set { defaults.set(newValue, forKey: fitKey) }
    }

    public var showImageInformation: Bool {
        get { defaults.bool(forKey: infoKey) }
        set { defaults.set(newValue, forKey: infoKey) }
    }
}
