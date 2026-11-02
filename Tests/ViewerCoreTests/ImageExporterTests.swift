import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ViewerCore

final class ImageExporterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func source(width: Int = 8, height: Int = 4, orientation: Int = 1) throws -> URL {
        let url = folder.appendingPathComponent("original.png")
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Left half red, right half transparent.
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, ctx.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return url
    }

    func testExportAppliesEditsAndPreservesOriginal() throws {
        let input = try source()
        let original = try Data(contentsOf: input)
        let output = folder.appendingPathComponent("edited.png")
        try ImageExporter.write(source: input, edits: [.crop(CGRect(x: 0, y: 0, width: 0.5, height: 1)), .rotateRight], to: output, format: .png)
        let loaded = try LoadedImage(url: output)
        XCTAssertEqual(loaded.bitmap.width, 4)
        XCTAssertEqual(loaded.bitmap.height, 4)
        let data = try XCTUnwrap(loaded.bitmap.dataProvider?.data) as Data
        XCTAssertGreaterThan(data[0], 240) // Red crop survived the pipeline.
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testExportUsesFullResolutionInsteadOf6000PixelPreview() throws {
        let input = try source(width: 6002, height: 2)
        XCTAssertEqual(try LoadedImage(url: input).bitmap.width, 6000)
        let output = folder.appendingPathComponent("full.tiff")
        try ImageExporter.write(source: input, edits: [], to: output, format: .tiff)
        XCTAssertEqual(try LoadedImage(url: output, maxPixelSize: nil).bitmap.width, 6002)
    }

    func testJPEGUsesWhiteForTransparency() throws {
        let input = try source(width: 40, height: 20)
        let output = folder.appendingPathComponent("white.jpg")
        try ImageExporter.write(source: input, edits: [], to: output, format: .jpeg)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let ctx = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 20))
        let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for channel in 0..<3 { XCTAssertGreaterThan(pixels[(10 * 40 + 35) * 4 + channel], 245) }
    }

    func testReplacingSourceAppliesOrientationOnlyOnce() throws {
        let input = try source(orientation: 6)
        try ImageExporter.write(source: input, edits: [.rotateRight], to: input, format: .png)
        let loaded = try LoadedImage(url: input)
        XCTAssertEqual(loaded.bitmap.width, 8)
        XCTAssertEqual(loaded.bitmap.height, 4)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(input as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
        XCTAssertEqual(properties?[kCGImagePropertyOrientation as String] as? Int ?? 1, 1)
    }

    func testFailedWriteLeavesSourceUntouched() throws {
        let input = try source()
        let original = try Data(contentsOf: input)
        XCTAssertThrowsError(try ImageExporter.write(source: input, edits: [.rotateRight], to: folder, format: .png))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testResizeRotationAndCropExportAtTheRequestedSize() throws {
        let input = try source()
        let output = folder.appendingPathComponent("resized.png")
        let edits: [ImageEdit] = [.resize(width: 240, height: 120), .rotateRight,
                                  .crop(CGRect(x: 0, y: 0, width: 0.5, height: 1))]
        try ImageExporter.write(source: input, edits: edits, to: output, format: .png)
        let saved = try LoadedImage(url: output)
        XCTAssertEqual(saved.bitmap.width, 60)
        XCTAssertEqual(saved.bitmap.height, 240)
        XCTAssertEqual(saved.size, CGSize(width: 60, height: 240))
    }

    func testFileTypeComesFromContentRatherThanExtension() throws {
        let input = try source()
        let renamed = folder.appendingPathComponent("misnamed.jpg")
        try FileManager.default.copyItem(at: input, to: renamed)
        XCTAssertEqual(try LoadedImage(url: renamed).fileType, "PNG")
    }
}
