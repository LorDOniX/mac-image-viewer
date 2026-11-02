import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import ViewerCore

final class AdvancedExportTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func source(_ name: String, metadata: Bool = false) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let context = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let encoder = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var properties: [CFString: Any] = [:]
        if metadata {
            properties = [kCGImagePropertyOrientation: 6,
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 2.8, kCGImagePropertyExifDateTimeOriginal: "2026:11:02 12:00:00"],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Test Camera"],
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 50.0, kCGImagePropertyGPSLatitudeRef: "N",
                                               kCGImagePropertyGPSLongitude: 14.0, kCGImagePropertyGPSLongitudeRef: "E"]]
        }
        CGImageDestinationAddImage(encoder, context.makeImage()!, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return url
    }
    private func properties(_ url: URL) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    }

    func testPreservedEXIFHasCorrectOutputOrientationAndDimensions() throws {
        let input = try source("camera.jpg", metadata: true)
        let output = folder.appendingPathComponent("kept.jpg")
        try ImageExporter.write(source: input, edits: [.rotateRight, .resize(width: 20, height: 10)], to: output,
                                format: .jpeg, settings: ExportSettings(preserveMetadata: true, removeGPS: false))
        let props = try properties(output)
        let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifFNumber as String] as? Double, 2.8)
        XCTAssertEqual(exif[kCGImagePropertyExifPixelXDimension as String] as? Int, 20)
        XCTAssertEqual(exif[kCGImagePropertyExifPixelYDimension as String] as? Int, 10)
        XCTAssertEqual(props[kCGImagePropertyOrientation as String] as? Int ?? 1, 1)
        XCTAssertNotNil(props[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(try LoadedImage(url: output).size, CGSize(width: 20, height: 10))
    }
    func testGPSCanBeRemovedWithoutRemovingEXIF() throws {
        let input = try source("gps.jpg", metadata: true)
        let output = folder.appendingPathComponent("private.jpg")
        try ImageExporter.write(source: input, edits: [], to: output, format: .jpeg,
                                settings: ExportSettings(preserveMetadata: true, removeGPS: true))
        let props = try properties(output)
        XCTAssertNil(props[kCGImagePropertyGPSDictionary as String])
        let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, "2026:11:02 12:00:00")
    }
    func testBatchAvoidsNameCollisionsAndAppliesEditsBeforeFitResize() throws {
        let a = try source("photo.jpg"), b = try source("photo.jpeg")
        let before = try Data(contentsOf: a)
        let output = folder.appendingPathComponent("batch")
        let result = try BatchExporter.write(sources: [a, b], histories: [a: [.rotateRight]], directory: output,
                                              format: .png, settings: ExportSettings(), resize: CGSize(width: 120, height: 120))
        XCTAssertEqual(result.saved.count, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(result.saved.values.map(\.lastPathComponent)), ["photo-upraveno.png", "photo-upraveno-2.png"])
        XCTAssertEqual(try LoadedImage(url: XCTUnwrap(result.saved[a])).size, CGSize(width: 60, height: 120))
        XCTAssertEqual(try LoadedImage(url: XCTUnwrap(result.saved[b])).size, CGSize(width: 120, height: 60))
        XCTAssertEqual(try Data(contentsOf: a), before)
    }
    func testBatchReportsFailuresAndContinuesWithOtherFiles() throws {
        let a = try source("valid.jpg")
        let bad = folder.appendingPathComponent("bad.jpg")
        try Data("broken".utf8).write(to: bad)
        let progress = Progress(totalUnitCount: 2)
        let result = try BatchExporter.write(sources: [bad, a], histories: [:], directory: folder.appendingPathComponent("batch"), format: .png, settings: ExportSettings(), progress: progress)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.saved.count, 1)
        XCTAssertEqual(progress.completedUnitCount, 2)
    }
    func testBatchCancellationAndExistingDirectoryNeverOverwriteFiles() throws {
        let a = try source("original.jpg")
        let before = try Data(contentsOf: a)
        let progress = Progress(totalUnitCount: 1); progress.cancel()
        let output = folder.appendingPathComponent("cancelled")
        let result = try BatchExporter.write(sources: [a], histories: [:], directory: output, format: .png, settings: ExportSettings(), progress: progress)
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.saved.isEmpty)
        XCTAssertThrowsError(try BatchExporter.write(sources: [a], histories: [:], directory: output, format: .png, settings: ExportSettings()))
        XCTAssertEqual(try Data(contentsOf: a), before)
    }
    func testJPEGQualityAffectsEncodedOutput() throws {
        let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var seed: UInt32 = 42
        for index in 0..<(128 * 128) {
            for channel in 0..<3 { seed = seed &* 1664525 &+ 1013904223; pixels[index * 4 + channel] = UInt8(seed >> 24) }
            pixels[index * 4 + 3] = 255
        }
        let input = folder.appendingPathComponent("noise.png")
        let encoder = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let low = folder.appendingPathComponent("low.jpg"), high = folder.appendingPathComponent("high.jpg")
        try ImageExporter.write(source: input, edits: [], to: low, format: .jpeg, settings: ExportSettings(quality: 0.1))
        try ImageExporter.write(source: input, edits: [], to: high, format: .jpeg, settings: ExportSettings(quality: 1))
        XCTAssertGreaterThan(try Data(contentsOf: high).count, try Data(contentsOf: low).count * 2)
    }
    func testInvalidBatchDimensionsDoNotCreateOutput() throws {
        let input = try source("original.jpg")
        let output = folder.appendingPathComponent("invalid")
        for size in [CGSize(width: 0, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10.5, height: 10)] {
            XCTAssertThrowsError(try BatchExporter.write(sources: [input], histories: [:], directory: output, format: .png, settings: ExportSettings(), resize: size))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testBatchWritesToCurrentDirectoryWithoutReplacingExistingFiles() throws {
        let input = try source("photo.jpg")
        let original = try Data(contentsOf: input)
        let existing = folder.appendingPathComponent("photo-upraveno.png")
        let marker = Data("existing output".utf8)
        try marker.write(to: existing)
        let result = try BatchExporter.write(sources: [input], histories: [:], directory: folder,
            format: .png, settings: ExportSettings(), resize: CGSize(width: 20, height: 10), keepAspect: false,
            operations: [.rotateRight], createDirectory: false)
        let output = try XCTUnwrap(result.saved[input])
        XCTAssertEqual(output.lastPathComponent, "photo-upraveno-2.png")
        XCTAssertEqual(try LoadedImage(url: output).size, CGSize(width: 20, height: 10))
        XCTAssertEqual(try LoadedImage(url: output).fileType, "PNG")
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(try Data(contentsOf: existing), marker)
    }
    func testBatchWritesIntoChosenExistingDirectoryAndRotatesSelection() throws {
        let a = try source("first.jpg"), b = try source("second.jpg")
        let output = folder.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let result = try BatchExporter.write(sources: [a, b], histories: [:], directory: output,
            format: .png, settings: ExportSettings(), operations: [.rotateLeft], createDirectory: false)
        XCTAssertEqual(result.saved.count, 2)
        for url in result.saved.values {
            XCTAssertEqual(url.deletingLastPathComponent().path, output.path)
            XCTAssertEqual(try LoadedImage(url: url).size, CGSize(width: 40, height: 80))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("first-upraveno.png").path))
    }
    func testBatchCanKeepEachOriginalFormat() throws {
        let jpeg = try source("camera.jpg")
        let png = folder.appendingPathComponent("screen.png")
        try ImageExporter.write(source: jpeg, edits: [], to: png, format: .png)
        let result = try BatchExporter.write(sources: [jpeg, png], histories: [:], directory: folder.appendingPathComponent("mixed"),
            format: .tiff, settings: ExportSettings(), keepOriginalFormat: true)
        let jpegOutput = try XCTUnwrap(result.saved[jpeg]), pngOutput = try XCTUnwrap(result.saved[png])
        XCTAssertEqual(jpegOutput.pathExtension, "jpg")
        XCTAssertEqual(pngOutput.pathExtension, "png")
        XCTAssertEqual(try LoadedImage(url: jpegOutput).fileType, "JPEG")
        XCTAssertEqual(try LoadedImage(url: pngOutput).fileType, "PNG")
    }
    func testReduceOnlyDoesNotEnlargeSmallerPictures() throws {
        let input = try source("small.jpg")
        let result = try BatchExporter.write(sources: [input], histories: [:], directory: folder.appendingPathComponent("fit"),
            format: .png, settings: ExportSettings(), resize: CGSize(width: 1000, height: 1000), operations: [.rotateRight], onlyReduce: true)
        XCTAssertEqual(try LoadedImage(url: XCTUnwrap(result.saved[input])).size, CGSize(width: 40, height: 80))
        let independent = try BatchExporter.write(sources: [input], histories: [:], directory: folder.appendingPathComponent("independent"),
            format: .png, settings: ExportSettings(), resize: CGSize(width: 1000, height: 10), keepAspect: false, onlyReduce: true)
        XCTAssertEqual(try LoadedImage(url: XCTUnwrap(independent.saved[input])).size, CGSize(width: 80, height: 10))
    }
    func testNoOverwriteExportLeavesExistingDestinationAndNoStagingFiles() throws {
        let input = try source("photo.jpg")
        let output = folder.appendingPathComponent("output.png")
        let marker = Data("keep existing bytes".utf8)
        try marker.write(to: output)
        XCTAssertThrowsError(try ImageExporter.write(source: input, edits: [.rotateRight], to: output, format: .png, overwrite: false))
        XCTAssertEqual(try Data(contentsOf: output), marker)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".image-viewer-") })
    }
    func testExistingDirectoryModeRequiresARealDirectory() throws {
        let input = try source("photo.jpg")
        let missing = folder.appendingPathComponent("missing")
        XCTAssertThrowsError(try BatchExporter.write(sources: [input], histories: [:], directory: missing, format: .png, settings: ExportSettings(), createDirectory: false))
        XCTAssertThrowsError(try BatchExporter.write(sources: [input], histories: [:], directory: input, format: .png, settings: ExportSettings(), createDirectory: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

}
