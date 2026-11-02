import Foundation
import ImageIO

public struct BatchExportResult {
    public var saved: [URL: URL] = [:]
    public var failures: [String] = []
    public var cancelled = false
}

public enum BatchExporter {
    /// New-directory mode rejects an existing directory. Existing-directory mode
    /// creates uniquely named copies alongside existing files; it never replaces them.
    public static func write(sources: [URL], histories: [URL: [ImageEdit]], directory: URL,
                             format: ExportFormat, settings: ExportSettings, resize: CGSize? = nil,
                             keepAspect: Bool = true, progress: Progress? = nil,
                             operations: [ImageEdit] = [], createDirectory: Bool = true,
                             keepOriginalFormat: Bool = false, onlyReduce: Bool = false) throws -> BatchExportResult {
        if let resize {
            guard resize.width.isFinite, resize.height.isFinite,
                  resize.width.rounded() == resize.width, resize.height.rounded() == resize.height,
                  (1...30000).contains(resize.width), (1...30000).contains(resize.height),
                  ImageDimensions.isValid(width: Int(resize.width), height: Int(resize.height)) else {
                throw NSError(domain: "ImageViewer.Batch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Neplatné výstupní rozměry."])
            }
        }
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        } else {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        var result = BatchExportResult()
        var names = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).map { $0.lowercased() })
        for source in sources {
            if progress?.isCancelled == true { result.cancelled = true; break }
            var outputFormat = format
            if keepOriginalFormat,
               let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
               let identifier = CGImageSourceGetType(imageSource) as String? {
                outputFormat = ExportFormat.available.first { $0.type.identifier == identifier } ?? .png
            }
            let base = source.deletingPathExtension().lastPathComponent + "-upraveno"
            var name = base + "." + outputFormat.fileExtension
            var suffix = 2
            while names.contains(name.lowercased()) {
                name = "\(base)-\(suffix).\(outputFormat.fileExtension)"
                suffix += 1
            }
            names.insert(name.lowercased())
            let destination = directory.appendingPathComponent(name)
            do {
                try autoreleasepool {
                    var edits = (histories[source] ?? []) + operations
                    if let resize {
                        var target = resize
                        if keepAspect || onlyReduce {
                            let loaded = try LoadedImage(url: source, maxPixelSize: 32)
                            var current = EditableImage(bitmap: loaded.bitmap, size: loaded.size)
                            for edit in edits {
                                guard let next = current.applying(edit, maxPixelSize: 32) else { throw CocoaError(.fileReadCorruptFile) }
                                current = next
                            }
                            if keepAspect {
                                var factor = min(resize.width / current.size.width, resize.height / current.size.height)
                                if onlyReduce { factor = min(1, factor) }
                                target = CGSize(width: max(1, (current.size.width * factor).rounded()),
                                                height: max(1, (current.size.height * factor).rounded()))
                            } else if onlyReduce {
                                target = CGSize(width: min(resize.width, current.size.width), height: min(resize.height, current.size.height))
                            }
                        }
                        edits.append(.resize(width: Int(target.width), height: Int(target.height)))
                    }
                    try ImageExporter.write(source: source, edits: edits, to: destination, format: outputFormat, settings: settings, overwrite: false)
                }
                result.saved[source] = destination
            } catch { result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)") }
            progress?.completedUnitCount += 1
        }
        return result
    }
}
