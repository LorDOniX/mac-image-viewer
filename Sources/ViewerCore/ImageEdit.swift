import AppKit

public enum ImageEdit: Equatable {
    case rotateLeft, rotateRight, flipHorizontal, flipVertical
    /// Rectangle in normalized image coordinates, measured from the top left.
    case crop(CGRect)
    case resize(width: Int, height: Int)
}

public struct EditableImage {
    public let bitmap: CGImage
    public let size: CGSize

    public init(bitmap: CGImage, size: CGSize) {
        self.bitmap = bitmap
        self.size = size
    }

    public func applying(_ edit: ImageEdit, maxPixelSize: Int? = nil) -> EditableImage? {
        let width = CGFloat(bitmap.width), height = CGFloat(bitmap.height)
        if case .resize(let targetWidth, let targetHeight) = edit {
            guard ImageDimensions.isValid(width: targetWidth, height: targetHeight) else { return nil }
            let factor = maxPixelSize.map { min(1, CGFloat(max(1, $0)) / CGFloat(max(targetWidth, targetHeight))) } ?? 1
            let outputWidth = max(1, Int((CGFloat(targetWidth) * factor).rounded()))
            let outputHeight = max(1, Int((CGFloat(targetHeight) * factor).rounded()))
            let space = bitmap.colorSpace?.model == .rgb ? bitmap.colorSpace! : CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: nil, width: outputWidth, height: outputHeight,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
            guard let result = context.makeImage() else { return nil }
            return EditableImage(bitmap: result, size: CGSize(width: targetWidth, height: targetHeight))
        }
        if case .crop(let normalized) = edit {
            let rect = normalized.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
            let pixels = CGRect(x: rect.minX * width, y: rect.minY * height,
                                width: rect.width * width, height: rect.height * height).integral
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard let cropped = bitmap.cropping(to: pixels) else { return nil }
            // Keep actual output dimensions independent of the downsampled preview.
            let logical = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                                 width: rect.width * size.width, height: rect.height * size.height).integral
                .intersection(CGRect(origin: .zero, size: size))
            return EditableImage(bitmap: cropped, size: logical.size)
        }
        let rotates: Bool
        switch edit {
        case .rotateLeft, .rotateRight: rotates = true
        default: rotates = false
        }
        let outputWidth = rotates ? bitmap.height : bitmap.width
        let outputHeight = rotates ? bitmap.width : bitmap.height
        let space = bitmap.colorSpace?.model == .rgb ? bitmap.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: outputWidth, height: outputHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        switch edit {
        case .rotateLeft:
            context.translateBy(x: height, y: 0)
            context.rotate(by: .pi / 2)
        case .rotateRight:
            context.translateBy(x: 0, y: width)
            context.rotate(by: -.pi / 2)
        case .flipHorizontal:
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .flipVertical:
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
        case .crop, .resize: break
        }
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { return nil }
        return EditableImage(bitmap: result, size: rotates ? CGSize(width: size.height, height: size.width) : size)
    }
}

public enum ImageDimensions {
    public static func isValid(width: Int, height: Int) -> Bool {
        (1...30000).contains(width) && (1...30000).contains(height)
            && Int64(width) * Int64(height) <= 100_000_000
    }

    public static func matchingDimension(_ value: Int, original: CGSize, changedWidth: Bool) -> Int {
        let ratio = changedWidth ? original.height / original.width : original.width / original.height
        return max(1, Int((CGFloat(value) * ratio).rounded()))
    }
}
