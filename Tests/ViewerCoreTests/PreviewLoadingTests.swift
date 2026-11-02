import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ViewerCore

final class PreviewLoadingTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private func source() throws -> URL {
        let url = folder.appendingPathComponent("photo.png")
        let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return url
    }
    func testPreviewSizeFollowsRetinaViewportAndZoom() {
        XCTAssertEqual(PreviewSizing.pixelLimit(viewport: CGSize(width: 1500, height: 900), backingScale: 2, fitToWindow: true), 3072)
        XCTAssertEqual(PreviewSizing.pixelLimit(viewport: CGSize(width: 500, height: 300), backingScale: 1, fitToWindow: true), 1024)
        XCTAssertEqual(PreviewSizing.pixelLimit(viewport: CGSize(width: 500, height: 300), backingScale: 2, fitToWindow: false), 6000)
        XCTAssertEqual(PreviewSizing.pixelLimit(viewport: CGSize(width: 10000, height: 10000), backingScale: 2, fitToWindow: true), 6000)
    }
    func testQuickPreviewKeepsOriginalDimensionsAndCanBeUpgraded() throws {
        let url = try source()
        let quick = try LoadedImage(url: url, maxPixelSize: 400, preferEmbeddedThumbnail: true)
        XCTAssertEqual(quick.size, CGSize(width: 1200, height: 800))
        XCTAssertLessThanOrEqual(quick.decodedPixelSize, 400)
        XCTAssertTrue(quick.satisfies(pixelLimit: 400))
        XCTAssertFalse(quick.satisfies(pixelLimit: 1200))
        let full = try LoadedImage(url: url, maxPixelSize: nil)
        XCTAssertTrue(full.satisfies(pixelLimit: 6000)) // Source itself is smaller than the limit.
        XCTAssertEqual(full.size, quick.size)
    }
    func testDiskThumbnailSurvivesANewCacheInstance() throws {
        let url = try source()
        let cacheFolder = folder.appendingPathComponent("cache")
        let cache = ThumbnailDiskCache(directory: cacheFolder)
        let key = try XCTUnwrap(cache.key(for: url, pixelLimit: 240))
        XCTAssertNil(cache.load(key: key))
        let thumbnail = try XCTUnwrap(ImageThumbnail.load(url: url, maxPixelSize: 240))
        cache.store(thumbnail, key: key)
        let reopened = ThumbnailDiskCache(directory: cacheFolder)
        let loaded = try XCTUnwrap(reopened.load(key: key))
        XCTAssertEqual(loaded.width, 240)
        XCTAssertEqual(loaded.height, 160)
    }
    func testChangedSourceAndRequestedSizeInvalidateDiskThumbnail() throws {
        let url = try source()
        let cache = ThumbnailDiskCache(directory: folder.appendingPathComponent("cache"))
        let oldKey = try XCTUnwrap(cache.key(for: url, pixelLimit: 240))
        let otherSize = try XCTUnwrap(cache.key(for: url, pixelLimit: 480))
        XCTAssertNotEqual(oldKey, otherSize)
        cache.store(try XCTUnwrap(ImageThumbnail.load(url: url, maxPixelSize: 240)), key: oldKey)
        try Data("changed contents".utf8).write(to: url)
        let changedKey = try XCTUnwrap(cache.key(for: url, pixelLimit: 240))
        XCTAssertNotEqual(oldKey, changedKey)
        XCTAssertNil(cache.load(key: changedKey))
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(cache.key(for: url))
    }
    func testInvalidDiskCacheKeysCannotEscapeCacheDirectory() throws {
        let cacheFolder = folder.appendingPathComponent("cache")
        let cache = ThumbnailDiskCache(directory: cacheFolder)
        let image = try XCTUnwrap(ImageThumbnail.load(url: source(), maxPixelSize: 240))
        cache.store(image, key: "../outside")
        XCTAssertNil(cache.load(key: "../outside"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFolder.path))
    }
}
