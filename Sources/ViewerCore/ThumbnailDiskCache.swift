import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

public final class ThumbnailDiskCache {
    private let directory: URL
    private let byteLimit: Int
    private let maintenance = DispatchQueue(label: "ImageViewer.ThumbnailCache", qos: .utility)
    private var lastPrune = Date.distantPast

    public init(directory: URL? = nil, byteLimit: Int = 256 * 1024 * 1024) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cz.romanmakudera.imageviewer/Thumbnails-v1", isDirectory: true)
        self.byteLimit = byteLimit
    }

    public func key(for url: URL, pixelLimit: Int = 440) -> String? {
        // URL resourceValues can remain cached after a file is replaced or removed.
        // Read fresh stat attributes so edited photos cannot reuse obsolete previews.
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = values[.size] as? NSNumber, let modified = values[.modificationDate] as? Date else { return nil }
        let signature = "v1|\(url.standardizedFileURL.absoluteString)|\(size)|\(modified.timeIntervalSince1970.bitPattern)|\(pixelLimit)"
        return SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func load(key: String) -> CGImage? {
        guard let url = cacheURL(key), FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    public func store(_ image: CGImage, key: String) {
        guard let url = cacheURL(key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            try (data as Data).write(to: url, options: .atomic)
            maintenance.async { [self] in pruneIfNeeded() }
        } catch { /* Disk cache is optional, including on read-only or full disks. */ }
    }

    private func cacheURL(_ key: String) -> URL? {
        guard key.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return directory.appendingPathComponent(key + ".png")
    }

    private func pruneIfNeeded() {
        guard Date().timeIntervalSince(lastPrune) > 60 else { return }
        lastPrune = Date()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let entries = urls.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        for entry in entries.sorted(by: { $0.2 < $1.2 }) where bytes > byteLimit {
            if (try? FileManager.default.removeItem(at: entry.0)) != nil { bytes -= entry.1 }
        }
    }
}
