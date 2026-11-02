import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import ViewerCore

final class ImageFolderTests: XCTestCase {
    func testFolderFiltersAndSortsNaturally() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["foto10.jpg", "foto2.jpg", "foto1.PNG", "notes.txt", ".hidden.jpg", "document.pdf"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.jpg"), withIntermediateDirectories: true)
        let files = try ImageFolder.images(beside: folder.appendingPathComponent("foto2.jpg"))
        XCTAssertEqual(files.map(\.lastPathComponent), ["foto1.PNG", "foto2.jpg", "foto10.jpg"])
    }

    func testNavigationWrapsAtFolderBoundaries() {
        XCTAssertEqual(ImageFolder.nextIndex(current: 0, step: -1, count: 3), 2)
        XCTAssertEqual(ImageFolder.nextIndex(current: 2, step: 1, count: 3), 0)
        XCTAssertEqual(ImageFolder.nextIndex(current: 1, step: 1, count: 3), 2)
        XCTAssertEqual(ImageFolder.nextIndex(current: 1, step: -1, count: 3), 0)
        XCTAssertEqual(ImageFolder.nextIndex(current: 0, step: -1, count: 1), 0)
        XCTAssertEqual(ImageFolder.nextIndex(current: 0, step: 1, count: 1), 0)
        XCTAssertEqual(ImageFolder.nextIndex(current: 0, step: -4, count: 3), 2)
        XCTAssertEqual(ImageFolder.nextIndex(current: 2, step: 4, count: 3), 0)
        XCTAssertNil(ImageFolder.nextIndex(current: 0, step: 1, count: 0))
        XCTAssertNil(ImageFolder.nextIndex(current: -1, step: 1, count: 3))
        XCTAssertNil(ImageFolder.nextIndex(current: 3, step: -1, count: 3))
    }

    func testDecodeRespectsEXIFOrientationAndReadsMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 2.8, kCGImagePropertyExifDateTimeOriginal: "2026:11:01 12:00:00"]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loaded = try LoadedImage(url: url)
        XCTAssertEqual(loaded.size.width, 20)
        XCTAssertEqual(loaded.size.height, 40)
        XCTAssertEqual(loaded.bitmap.width, 20)
        XCTAssertEqual(loaded.bitmap.height, 40)
        XCTAssertTrue(loaded.details.contains("Clona: f/2.8"))
        XCTAssertTrue(loaded.details.contains("2026:11:01 12:00:00"))
        let json = try loaded.metadataJSON()
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let exif = try XCTUnwrap(metadata[kCGImagePropertyExifDictionary as String] as? [String: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifFNumber as String] as? Double, 2.8)
        XCTAssertEqual(metadata[kCGImagePropertyOrientation as String] as? Int, 6)
    }

    func testCorruptImageReturnsAnError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try LoadedImage(url: url))
    }
}
