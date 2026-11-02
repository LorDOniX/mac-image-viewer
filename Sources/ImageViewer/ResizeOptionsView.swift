import AppKit
import ViewerCore

final class ResizeOptionsView: NSView, NSTextFieldDelegate {
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let keepRatio = NSButton(checkboxWithTitle: "Zachovat poměr stran", target: nil, action: nil)
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let original: CGSize
    private weak var confirmButton: NSButton?
    private var lastChangedWidth = true

    var dimensions: (width: Int, height: Int)? {
        guard let width = integer(widthField), let height = integer(heightField),
              ImageDimensions.isValid(width: width, height: height) else { return nil }
        return (width, height)
    }

    init(size: CGSize, confirmButton: NSButton) {
        original = size
        self.confirmButton = confirmButton
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 142))
        widthField.stringValue = String(Int(size.width.rounded()))
        heightField.stringValue = String(Int(size.height.rounded()))
        for (label, field, y) in [("Šířka (px):", widthField, 110.0), ("Výška (px):", heightField, 76.0)] {
            let title = NSTextField(labelWithString: label)
            title.frame = NSRect(x: 0, y: y, width: 100, height: 22)
            field.frame = NSRect(x: 110, y: y, width: 180, height: 24)
            field.delegate = self
            addSubview(title)
            addSubview(field)
        }
        widthField.setAccessibilityLabel("Šířka v pixelech")
        heightField.setAccessibilityLabel("Výška v pixelech")
        keepRatio.frame = NSRect(x: 0, y: 42, width: 300, height: 24)
        keepRatio.state = .on
        keepRatio.target = self
        keepRatio.action = #selector(ratioChanged)
        addSubview(keepRatio)
        errorLabel.frame = NSRect(x: 0, y: 0, width: 320, height: 36)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .secondaryLabelColor
        addSubview(errorLabel)
        updateValidation()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func integer(_ field: NSTextField) -> Int? {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(text)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        lastChangedWidth = field === widthField
        synchronizeRatio()
        updateValidation()
    }

    @objc private func ratioChanged() { synchronizeRatio(); updateValidation() }

    private func synchronizeRatio() {
        guard keepRatio.state == .on,
              let value = integer(lastChangedWidth ? widthField : heightField), (1...30000).contains(value) else { return }
        let matching = ImageDimensions.matchingDimension(value, original: original, changedWidth: lastChangedWidth)
        (lastChangedWidth ? heightField : widthField).stringValue = String(matching)
    }

    private func updateValidation() {
        let valid = dimensions != nil
        confirmButton?.isEnabled = valid
        errorLabel.stringValue = valid ? "" : "Zadejte celé rozměry 1–30 000 px, nejvýše 100 megapixelů."
    }
}
