import AppKit
import ImageIO
import UniformTypeIdentifiers

public final class LoadedImage: NSObject {
    public let bitmap: CGImage
    public let size: NSSize
    public let details: String
    public let fileType: String
    private let metadata: [String: Any]
    public var metadataProperties: [String: Any] { metadata }
    public var cost: Int { bitmap.bytesPerRow * bitmap.height }

    public func metadataJSON() throws -> String { try MetadataJSON.encode(metadata) }

    public init(url: URL, maxPixelSize: Int? = 6000) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw NSError(domain: "ImageViewer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Soubor nelze přečíst jako obrázek."])
        }
        let identifier = CGImageSourceGetType(source) as String? ?? ""
        let names = ["public.jpeg": "JPEG", "public.png": "PNG", "public.tiff": "TIFF",
                     "public.heic": "HEIC", "public.heif": "HEIF", "org.webmproject.webp": "WebP",
                     "com.microsoft.bmp": "BMP", "com.compuserve.gif": "GIF"]
        fileType = names[identifier] ?? UTType(identifier)?.preferredFilenameExtension?.uppercased() ?? identifier
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        metadata = properties
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize ?? max(
                (properties[kCGImagePropertyPixelWidth as String] as? Int) ?? 1,
                (properties[kCGImagePropertyPixelHeight as String] as? Int) ?? 1),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw NSError(domain: "ImageViewer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Obrázek je poškozený nebo jeho formát není podporovaný."])
        }
        self.bitmap = bitmap
        let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? Double(bitmap.width)
        let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? Double(bitmap.height)
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        self.size = (5...8).contains(orientation) ? NSSize(width: height, height: width) : NSSize(width: width, height: height)
        var lines = [url.lastPathComponent, "", "Rozměry: \(Int(width)) × \(Int(height)) px"]
        if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            lines.append("Velikost: \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
        }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        func add(_ label: String, _ value: Any?) {
            if let value { lines.append("\(label): \(value)") }
        }
        add("Pořízeno", exif[kCGImagePropertyExifDateTimeOriginal as String])
        add("Výrobce", tiff[kCGImagePropertyTIFFMake as String])
        add("Fotoaparát", tiff[kCGImagePropertyTIFFModel as String])
        add("Objektiv", exif[kCGImagePropertyExifLensModel as String])
        if let time = exif[kCGImagePropertyExifExposureTime as String] as? Double, time > 0 {
            add("Čas", time < 1 ? "1/\(Int((1 / time).rounded())) s" : "\(time) s")
        }
        if let f = exif[kCGImagePropertyExifFNumber as String] { add("Clona", "f/\(f)") }
        if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber] {
            add("ISO", iso.map { $0.stringValue }.joined(separator: ", "))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength as String] { add("Ohnisko", "\(focal) mm") }
        if exif.isEmpty { lines.append("\nSoubor neobsahuje EXIF.") }
        lines += ["", "VŠECHNA METADATA", ""]
        func flatten(_ dictionary: [String: Any], indent: String = "") {
            for key in dictionary.keys.sorted() {
                guard let value = dictionary[key] else { continue }
                if let nested = value as? [String: Any] {
                    lines.append("\(indent)\(key)")
                    flatten(nested, indent: indent + "  ")
                } else if !(value is Data) {
                    lines.append("\(indent)\(key): \(value)")
                }
            }
        }
        flatten(properties)
        details = lines.joined(separator: "\n")
    }
}
