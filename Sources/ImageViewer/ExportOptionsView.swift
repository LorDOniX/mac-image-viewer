import AppKit
import ViewerCore

final class ExportOptionsView: NSView {
    private let popup = NSPopUpButton()
    private let formats = ExportFormat.available
    private weak var panel: NSSavePanel?
    private let quality = NSSlider(value: 90, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: "Kvalita: 90 %")
    private let preserve = NSButton(checkboxWithTitle: "Zachovat EXIF a další metadata", target: nil, action: nil)
    private let removeGPS = NSButton(checkboxWithTitle: "Vynechat GPS souřadnice", target: nil, action: nil)
    private let resize = NSButton(checkboxWithTitle: "Změnit rozměry (šířka × výška v px)", target: nil, action: nil)
    private let widthField = NSTextField(string: "1920")
    private let heightField = NSTextField(string: "1080")
    private let aspect = NSButton(checkboxWithTitle: "Zachovat poměr stran – vejít do rozměrů", target: nil, action: nil)
    var format: ExportFormat { formats[popup.indexOfSelectedItem] }
    var settings: ExportSettings { ExportSettings(quality: quality.doubleValue / 100, preserveMetadata: preserve.state == .on, removeGPS: removeGPS.state == .on) }
    var resizeTo: CGSize? { resize.state == .on ? CGSize(width: widthField.integerValue, height: heightField.integerValue) : nil }
    var keepAspect: Bool { aspect.state == .on }
    var validResize: Bool { resize.state != .on || ImageDimensions.isValid(width: widthField.integerValue, height: heightField.integerValue) }

    init(panel: NSSavePanel? = nil, batch: Bool = false) {
        self.panel = panel
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: batch ? 270 : 160))
        let top = frame.height
        let label = NSTextField(labelWithString: "Formát:")
        label.frame = NSRect(x: 12, y: top - 34, width: 65, height: 18)
        popup.frame = NSRect(x: 80, y: top - 39, width: 280, height: 28)
        popup.addItems(withTitles: formats.map(\.title))
        popup.target = self; popup.action = #selector(formatChanged)
        qualityLabel.frame = NSRect(x: 12, y: top - 68, width: 125, height: 18)
        quality.frame = NSRect(x: 145, y: top - 73, width: 215, height: 24)
        quality.target = self; quality.action = #selector(updateControls)
        preserve.frame = NSRect(x: 12, y: top - 108, width: 350, height: 24)
        removeGPS.frame = NSRect(x: 12, y: top - 139, width: 350, height: 24)
        preserve.state = .on; removeGPS.state = .on
        preserve.target = self; preserve.action = #selector(updateControls)
        for child in [label, popup, qualityLabel, quality, preserve, removeGPS] { addSubview(child) }
        if batch {
            resize.frame = NSRect(x: 12, y: top - 176, width: 360, height: 24)
            widthField.frame = NSRect(x: 22, y: top - 210, width: 130, height: 24)
            heightField.frame = NSRect(x: 174, y: top - 210, width: 130, height: 24)
            aspect.frame = NSRect(x: 12, y: 10, width: 360, height: 24)
            aspect.state = .on
            resize.target = self; resize.action = #selector(updateControls)
            widthField.setAccessibilityLabel("Výstupní šířka"); heightField.setAccessibilityLabel("Výstupní výška")
            for child in [resize, widthField, heightField, aspect] { addSubview(child) }
        }
        formatChanged()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func formatChanged() {
        if let panel {
            let name = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = name + "." + format.fileExtension
            panel.allowedContentTypes = [format.type]
        }
        updateControls()
    }
    @objc private func updateControls() {
        qualityLabel.stringValue = "Kvalita: \(Int(quality.doubleValue)) %"
        quality.isEnabled = format == .jpeg || format == .heic
        qualityLabel.textColor = quality.isEnabled ? .labelColor : .secondaryLabelColor
        removeGPS.isEnabled = preserve.state == .on
        widthField.isEnabled = resize.state == .on
        heightField.isEnabled = resize.state == .on
        aspect.isEnabled = resize.state == .on
    }
}
