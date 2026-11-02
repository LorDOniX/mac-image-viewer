import Foundation

public struct BatchExportResult {
    public var saved: [URL: URL] = [:]
    public var failures: [String] = []
    public var cancelled = false
}

public enum BatchExporter {
    /// The output directory must be new: originals and existing exports are never replaced.
    public static func write(sources: [URL], histories: [URL: [ImageEdit]], directory: URL,
                             format: ExportFormat, settings: ExportSettings, resize: CGSize? = nil,
                             keepAspect: Bool = true, progress: Progress? = nil) throws -> BatchExportResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var result = BatchExportResult()
        var names = Set<String>()
        for source in sources {
            if progress?.isCancelled == true { result.cancelled = true; break }
            let base = source.deletingPathExtension().lastPathComponent + "-upraveno"
            var name = base + "." + format.fileExtension
            var suffix = 2
            while names.contains(name.lowercased()) {
                name = "\(base)-\(suffix).\(format.fileExtension)"
                suffix += 1
            }
            names.insert(name.lowercased())
            let destination = directory.appendingPathComponent(name)
            do {
                try autoreleasepool {
                    var edits = histories[source] ?? []
                    if let resize {
                        var target = resize
                        if keepAspect {
                            let loaded = try LoadedImage(url: source, maxPixelSize: 32)
                            var current = EditableImage(bitmap: loaded.bitmap, size: loaded.size)
                            for edit in edits {
                                guard let next = current.applying(edit, maxPixelSize: 32) else { throw CocoaError(.fileReadCorruptFile) }
                                current = next
                            }
                            let factor = min(resize.width / current.size.width, resize.height / current.size.height)
                            target = CGSize(width: max(1, (current.size.width * factor).rounded()),
                                            height: max(1, (current.size.height * factor).rounded()))
                        }
                        edits.append(.resize(width: Int(target.width), height: Int(target.height)))
                    }
                    try ImageExporter.write(source: source, edits: edits, to: destination, format: format, settings: settings)
                }
                result.saved[source] = destination
            } catch { result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)") }
            progress?.completedUnitCount += 1
        }
        return result
    }
}
