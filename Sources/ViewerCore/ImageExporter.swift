import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: String, CaseIterable {
    case png, jpeg, tiff, heic

    public var title: String {
        switch self {
        case .png: return "PNG (.png)"
        case .jpeg: return "JPEG (.jpg)"
        case .tiff: return "TIFF (.tiff)"
        case .heic: return "HEIC (.heic)"
        }
    }
    public var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .heic: return .heic
        }
    }
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public static var available: [ExportFormat] {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as! [String]
        return allCases.filter { identifiers.contains($0.type.identifier) }
    }
}

public struct ExportSettings {
    public var quality: Double
    public var preserveMetadata: Bool
    public var removeGPS: Bool
    public init(quality: Double = 0.9, preserveMetadata: Bool = false, removeGPS: Bool = true) {
        self.quality = quality
        self.preserveMetadata = preserveMetadata
        self.removeGPS = removeGPS
    }
}

public enum ImageExporter {
    public static func write(source: URL, edits: [ImageEdit], to destination: URL, format: ExportFormat, settings: ExportSettings = ExportSettings()) throws {
        // Export starts from the original resolution, independently of the preview,
        // window size, zoom or pan. ImageIO applies the original EXIF orientation.
        let loaded = try LoadedImage(url: source, maxPixelSize: nil)
        var image = EditableImage(bitmap: loaded.bitmap, size: loaded.size)
        for edit in edits {
            guard let next = autoreleasepool(invoking: { image.applying(edit) }) else {
                throw failure("Úpravu obrázku se nepodařilo provést.")
            }
            image = next
        }
        var bitmap = image.bitmap
        if format == .jpeg {
            // JPEG has no alpha channel; transparent areas become white.
            guard let context = CGContext(data: nil, width: bitmap.width, height: bitmap.height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw failure("Nelze připravit obrázek pro JPEG.")
            }
            let rect = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            context.draw(bitmap, in: rect)
            guard let flattened = context.makeImage() else { throw failure("Nelze připravit JPEG.") }
            bitmap = flattened
        }
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
            throw failure("Vybraný formát nelze na tomto systému uložit.")
        }
        var properties = exportMetadata(loaded.metadataProperties, width: bitmap.width, height: bitmap.height, settings: settings)
        properties[kCGImageDestinationLossyCompressionQuality as String] = min(1, max(0, settings.quality))
        CGImageDestinationAddImage(encoder, bitmap, properties as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw failure("Obrázek se nepodařilo zakódovat.") }
        // Encode completely before touching the destination, also when replacing
        // the source file after the system Save panel's overwrite confirmation.
        try (data as Data).write(to: destination, options: .atomic)
    }

    public static func exportMetadata(_ source: [String: Any], width: Int, height: Int, settings: ExportSettings) -> [String: Any] {
        guard settings.preserveMetadata else { return [:] }
        var result: [String: Any] = [:]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyTIFFDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            result[key as String] = source[key as String]
        }
        result[kCGImagePropertyOrientation as String] = 1
        result[kCGImagePropertyPixelWidth as String] = width
        result[kCGImagePropertyPixelHeight as String] = height
        var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension as String] = width
        exif[kCGImagePropertyExifPixelYDimension as String] = height
        result[kCGImagePropertyExifDictionary as String] = exif
        if var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            result[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if settings.removeGPS { result.removeValue(forKey: kCGImagePropertyGPSDictionary as String) }
        return result
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ImageViewer.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
