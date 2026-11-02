import AppKit
import ViewerCore

enum BatchDestination: Int {
    case currentFolder, chosenFolder, newSubfolder
}

final class ExportOptionsView: NSView, NSTextFieldDelegate {
    var validationChanged: ((Bool) -> Void)?
    private let validationLabel = NSTextField(labelWithString: "")
    private let popup = NSPopUpButton()
    private let batch: Bool
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
    private let rotation = NSPopUpButton()
    private let destinationPopup = NSPopUpButton()
    private let reduceOnly = NSButton(checkboxWithTitle: "Pouze zmenšit, malé obrázky nezvětšovat", target: nil, action: nil)
    var keepOriginalFormat: Bool { batch && popup.indexOfSelectedItem == 0 }
    var format: ExportFormat { keepOriginalFormat ? .png : formats[popup.indexOfSelectedItem - (batch ? 1 : 0)] }
    var destination: BatchDestination { BatchDestination(rawValue: destinationPopup.indexOfSelectedItem) ?? .currentFolder }
    var onlyReduce: Bool { reduceOnly.state == .on }
    var operations: [ImageEdit] {
        switch rotation.indexOfSelectedItem {
        case 1: return [.rotateLeft]
        case 2: return [.rotateRight]
        case 3: return [.rotateRight, .rotateRight]
        default: return []
        }
    }
    var settings: ExportSettings { ExportSettings(quality: quality.doubleValue / 100, preserveMetadata: preserve.state == .on, removeGPS: removeGPS.state == .on) }
    var resizeTo: CGSize? { resize.state == .on ? CGSize(width: widthField.integerValue, height: heightField.integerValue) : nil }
    var keepAspect: Bool { aspect.state == .on }
    var validResize: Bool {
        if resize.state != .on { return true }
        guard let width = Int(widthField.stringValue), let height = Int(heightField.stringValue) else { return false }
        return ImageDimensions.isValid(width: width, height: height)
    }

    init(panel: NSSavePanel? = nil, batch: Bool = false) {
        self.panel = panel
        self.batch = batch
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: batch ? 440 : 160))
        let top = frame.height
        let label = NSTextField(labelWithString: "Formát:")
        label.frame = NSRect(x: 12, y: top - 34, width: 65, height: 18)
        popup.frame = NSRect(x: 80, y: top - 39, width: 280, height: 28)
        if batch { popup.addItem(withTitle: "Původní (jiné typy → PNG)") }
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
            aspect.frame = NSRect(x: 12, y: top - 243, width: 380, height: 24)
            aspect.state = .on
            resize.target = self; resize.action = #selector(updateControls)
            widthField.delegate = self; heightField.delegate = self
            widthField.setAccessibilityLabel("Výstupní šířka"); heightField.setAccessibilityLabel("Výstupní výška")
            reduceOnly.state = .on
            reduceOnly.frame = NSRect(x: 12, y: top - 273, width: 380, height: 24)
            let rotationLabel = NSTextField(labelWithString: "Rotace:")
            rotationLabel.frame = NSRect(x: 12, y: top - 307, width: 65, height: 18)
            rotation.frame = NSRect(x: 80, y: top - 312, width: 280, height: 28)
            rotation.addItems(withTitles: ["Bez otočení", "Doleva o 90°", "Doprava o 90°", "O 180°"])
            let destinationLabel = NSTextField(labelWithString: "Uložit do:")
            destinationLabel.frame = NSRect(x: 12, y: top - 344, width: 65, height: 18)
            destinationPopup.frame = NSRect(x: 80, y: top - 349, width: 280, height: 28)
            destinationPopup.addItems(withTitles: ["Aktuální složky obrázků", "Zvolené složky…", "Nové podsložky v aktuální složce"])
            let note = NSTextField(wrappingLabelWithString: "Vzniknou kopie s příponou -upraveno. Originály a existující soubory se nepřepisují.")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            note.frame = NSRect(x: 12, y: 10, width: 376, height: 40)
            validationLabel.frame = NSRect(x: 12, y: 56, width: 376, height: 20)
            validationLabel.font = .systemFont(ofSize: 11)
            validationLabel.textColor = .systemRed
            for child in [resize, widthField, heightField, aspect, reduceOnly, rotationLabel, rotation, destinationLabel, destinationPopup, validationLabel, note] { addSubview(child) }
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
    func controlTextDidChange(_ notification: Notification) { updateControls() }
    @objc private func updateControls() {
        qualityLabel.stringValue = "Kvalita: \(Int(quality.doubleValue)) %"
        quality.isEnabled = keepOriginalFormat || format == .jpeg || format == .heic
        qualityLabel.textColor = quality.isEnabled ? .labelColor : .secondaryLabelColor
        removeGPS.isEnabled = preserve.state == .on
        widthField.isEnabled = resize.state == .on
        heightField.isEnabled = resize.state == .on
        aspect.isEnabled = resize.state == .on
        reduceOnly.isEnabled = resize.state == .on
        validationLabel.stringValue = validResize ? "" : "Rozměry: 1–30 000 px, nejvýše 100 megapixelů."
        validationChanged?(validResize)
    }
}
