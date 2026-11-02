import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

public enum ImageFolder {
    public static func canonicalURL(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        let path = url.withUnsafeFileSystemRepresentation { pointer -> String? in
            guard let pointer, let resolved = realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        return path.map { URL(fileURLWithPath: $0, isDirectory: url.hasDirectoryPath) } ?? url.standardizedFileURL
    }
    private static let identifiers = CGImageSourceCopyTypeIdentifiers() as! [String]
    public static let supportedTypes: [UTType] = {
        let types = identifiers.compactMap { UTType($0) }
        return types.isEmpty ? [.jpeg, .png, .tiff, .bmp, .gif, .heic, .heif, .webP] : types
    }()
    // Launch Services can be unavailable in a command-line/test process. Common
    // extensions still work there without depending on its registration database.
    private static let extensions: [String: String] = [
        "jpg": "public.jpeg", "jpeg": "public.jpeg", "jpe": "public.jpeg",
        "png": "public.png", "tif": "public.tiff", "tiff": "public.tiff",
        "bmp": "com.microsoft.bmp", "gif": "com.compuserve.gif",
        "heic": "public.heic", "heif": "public.heif", "webp": "org.webmproject.webp"
    ]

    public static func supports(_ url: URL) -> Bool {
        if let identifier = extensions[url.pathExtension.lowercased()] {
            return identifiers.contains(identifier)
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    public static func images(beside url: URL) throws -> [URL] {
        let url = canonicalURL(url)
        let files = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )
        return files.filter {
            supports($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // Wrap in both directions so the first and last image are adjacent.
    public static func nextIndex(current: Int, step: Int, count: Int) -> Int? {
        guard count > 0, (0..<count).contains(current) else { return nil }
        let shift = step % count
        if shift >= 0 {
            return current >= count - shift ? current - (count - shift) : current + shift
        }
        return current < -shift ? count + (current + shift) : current + shift
    }
}
