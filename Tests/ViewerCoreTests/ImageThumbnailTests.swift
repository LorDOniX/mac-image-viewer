import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ViewerCore

final class ImageThumbnailTests: XCTestCase {
    func testThumbnailPreservesAspectRatioAndEXIFOrientation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let thumbnail = try XCTUnwrap(ImageThumbnail.load(url: url, maxPixelSize: 240))
        XCTAssertEqual(thumbnail.width, 160)
        XCTAssertEqual(thumbnail.height, 240)
        XCTAssertEqual(Double(thumbnail.width) / Double(thumbnail.height), 800.0 / 1200.0, accuracy: 0.001)
    }

    func testInvalidThumbnailLeavesAPlaceholderInsteadOfCrashing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("corrupt".utf8).write(to: url)
        XCTAssertNil(ImageThumbnail.load(url: url))
        XCTAssertNil(ImageThumbnail.load(url: url, maxPixelSize: 0))
    }
}
