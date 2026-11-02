import XCTest
import AppKit
@testable import ViewerCore

final class ImageEditTests: XCTestCase {
    // An asymmetric 3 × 2 image, with a different red-channel value in every pixel.
    private func fixture() -> EditableImage {
        let bytes: [UInt8] = [10, 20, 30, 40, 50, 60].flatMap { [$0, 0, 0, 255] }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let bitmap = CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return EditableImage(bitmap: bitmap, size: CGSize(width: 300, height: 200))
    }

    private func pixels(_ image: EditableImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.bitmap.width, height: image.bitmap.height,
                            bitsPerComponent: 8, bytesPerRow: image.bitmap.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image.bitmap, in: CGRect(x: 0, y: 0, width: image.bitmap.width, height: image.bitmap.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(image.bitmap.width * image.bitmap.height)).map { data[$0 * 4] }
    }

    func testRotationDirectionAndDimensions() throws {
        let right = try XCTUnwrap(fixture().applying(.rotateRight))
        XCTAssertEqual(pixels(right), [40, 10, 50, 20, 60, 30])
        XCTAssertEqual(right.size, CGSize(width: 200, height: 300))
        let left = try XCTUnwrap(fixture().applying(.rotateLeft))
        XCTAssertEqual(pixels(left), [30, 60, 20, 50, 10, 40])
        XCTAssertEqual(pixels(try XCTUnwrap(right.applying(.rotateLeft))), pixels(fixture()))
    }

    func testFlipsUseTheCorrectAxis() throws {
        XCTAssertEqual(pixels(try XCTUnwrap(fixture().applying(.flipHorizontal))), [30, 20, 10, 60, 50, 40])
        XCTAssertEqual(pixels(try XCTUnwrap(fixture().applying(.flipVertical))), [40, 50, 60, 10, 20, 30])
    }

    func testCropUsesTopLeftCoordinatesAndClampsToImage() throws {
        let crop = try XCTUnwrap(fixture().applying(.crop(CGRect(x: 0, y: 0, width: 1, height: 0.5))))
        XCTAssertEqual(pixels(crop), [10, 20, 30])
        XCTAssertEqual(crop.size, CGSize(width: 300, height: 100))
        let clamped = try XCTUnwrap(fixture().applying(.crop(CGRect(x: -1, y: -1, width: 2, height: 2))))
        XCTAssertEqual(pixels(clamped), pixels(fixture()))
        XCTAssertNil(fixture().applying(.crop(.zero)))
        XCTAssertNil(fixture().applying(.crop(CGRect(x: 2, y: 2, width: 1, height: 1))))
    }

    func testResizeKeepsOutputDimensionsWhenPreviewIsLimited() throws {
        let edit = ImageEdit.resize(width: 240, height: 120)
        let preview = try XCTUnwrap(fixture().applying(edit, maxPixelSize: 12))
        XCTAssertEqual(preview.bitmap.width, 12)
        XCTAssertEqual(preview.bitmap.height, 6)
        XCTAssertEqual(preview.size, CGSize(width: 240, height: 120))
        let rotated = try XCTUnwrap(preview.applying(.rotateRight))
        let cropped = try XCTUnwrap(rotated.applying(.crop(CGRect(x: 0, y: 0, width: 0.5, height: 1))))
        XCTAssertEqual(cropped.size, CGSize(width: 60, height: 240))
        let full = try XCTUnwrap(fixture().applying(edit))
        XCTAssertEqual(full.bitmap.width, 240)
        XCTAssertEqual(full.bitmap.height, 120)
        XCTAssertEqual(full.size, preview.size)
    }

    func testDimensionValidationAndLockedAspectRatio() {
        XCTAssertTrue(ImageDimensions.isValid(width: 1, height: 1))
        XCTAssertTrue(ImageDimensions.isValid(width: 10000, height: 10000))
        for (width, height) in [(0, 5), (5, -1), (30001, 1), (10000, 10001), (Int.max, Int.max)] {
            XCTAssertFalse(ImageDimensions.isValid(width: width, height: height))
            XCTAssertNil(fixture().applying(.resize(width: width, height: height)))
        }
        XCTAssertEqual(ImageDimensions.matchingDimension(40, original: CGSize(width: 300, height: 200), changedWidth: true), 27)
        XCTAssertEqual(ImageDimensions.matchingDimension(40, original: CGSize(width: 300, height: 200), changedWidth: false), 60)
    }
}
