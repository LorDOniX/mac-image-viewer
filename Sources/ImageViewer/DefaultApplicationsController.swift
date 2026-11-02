import AppKit
import UniformTypeIdentifiers

final class DefaultApplicationsController {
    private(set) var isBusy = false
    private let formats: [(title: String, type: UTType)] = [
        ("JPEG (.jpg, .jpeg)", .jpeg), ("PNG (.png)", .png),
        ("HEIC (.heic)", .heic), ("HEIF (.heif)", .heif),
        ("TIFF (.tif, .tiff)", .tiff), ("BMP (.bmp)", .bmp),
        ("WebP (.webp)", .webP), ("GIF (.gif)", .gif)
    ]

    func present(for window: NSWindow) {
        guard !isBusy, window.attachedSheet == nil else { return }
        let application = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard application.pathExtension == "app" else {
            let alert = NSAlert()
            alert.messageText = "Spusťte sestavenou aplikaci"
            alert.informativeText = "Nastavení výchozího prohlížeče je dostupné po spuštění Image Viewer.app ze složky dist nebo Aplikace."
            alert.beginSheetModal(for: window)
            return
        }
        isBusy = true
        let alert = NSAlert()
        alert.messageText = "Výchozí prohlížeč obrázků"
        alert.informativeText = "Image Viewer bude otevírat označené formáty při dvojkliku ve Finderu. macOS může požádat o potvrzení změny."
        let confirm = alert.addButton(withTitle: "Nastavit jako výchozí")
        alert.addButton(withTitle: "Zrušit")
        let choices = FormatChoices(formats: formats.map(\.title), confirm: confirm)
        alert.accessoryView = choices
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else { isBusy = false; return }
            let selected = choices.selectedIndices.map { formats[$0] }
            guard !selected.isEmpty else { isBusy = false; return }
            apply(selected, application: application, window: window)
        }
    }

    private func apply(_ selected: [(title: String, type: UTType)], application: URL, window: NSWindow) {
        let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
                               styleMask: [.titled], backing: .buffered, defer: false)
        progress.title = "Nastavení výchozího prohlížeče"
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 40, width: 24, height: 24))
        indicator.style = .spinning
        indicator.startAnimation(nil)
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 60, y: 40, width: 360, height: 22)
        progress.contentView?.addSubview(indicator)
        progress.contentView?.addSubview(label)
        window.beginSheet(progress)
        var successes: [String] = []
        var failures: [String] = []

        func next(_ index: Int) {
            guard index < selected.count else {
                window.endSheet(progress)
                progress.orderOut(nil)
                isBusy = false
                let result = NSAlert()
                result.messageText = failures.isEmpty ? "Výchozí prohlížeč je nastavený" : "Některé formáty se nepodařilo nastavit"
                var details: [String] = []
                if !successes.isEmpty { details.append("Nastaveno: " + successes.joined(separator: ", ") + ".") }
                if !failures.isEmpty { details.append("Nezměněno:\n" + failures.joined(separator: "\n")) }
                details.append("Další build ve stejné složce obvykle nevyžaduje nové nastavení. Po přesunutí aplikace jej můžete zopakovat.")
                result.informativeText = details.joined(separator: "\n\n")
                result.alertStyle = failures.isEmpty ? .informational : .warning
                result.beginSheetModal(for: window)
                return
            }
            let format = selected[index]
            label.stringValue = "\(index + 1) / \(selected.count) · \(format.title)"
            // Process one type at a time so system consent dialogs cannot overlap.
            NSWorkspace.shared.setDefaultApplication(at: application, toOpen: format.type) { error in
                DispatchQueue.main.async {
                    if let error {
                        failures.append("\(format.title): \(error.localizedDescription)")
                    } else {
                        successes.append(format.title)
                    }
                    next(index + 1)
                }
            }
        }
        next(0)
    }
}

private final class FormatChoices: NSView {
    private var checkboxes: [NSButton] = []
    private weak var confirm: NSButton?
    var selectedIndices: [Int] { checkboxes.indices.filter { checkboxes[$0].state == .on } }

    init(formats: [String], confirm: NSButton) {
        self.confirm = confirm
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: formats.count * 28))
        for (index, title) in formats.enumerated() {
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(selectionChanged))
            checkbox.state = .on
            checkbox.frame = NSRect(x: 0, y: (formats.count - index - 1) * 28, width: 360, height: 24)
            addSubview(checkbox)
            checkboxes.append(checkbox)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func selectionChanged() { confirm?.isEnabled = !selectedIndices.isEmpty }
}
