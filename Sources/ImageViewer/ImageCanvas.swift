import AppKit
import ViewerCore

final class ImageCanvas: NSView {
    var originalImage: NSImage?
    var stopSlideshow: (() -> Void)?
    private(set) var isComparing = false
    private var displayedImage: NSImage? { isComparing ? originalImage : image }
    func endComparison() { isComparing = false; needsDisplay = true; viewChanged?() }
    override func resignFirstResponder() -> Bool { endComparison(); return super.resignFirstResponder() }
    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.lowercased() == "b" { endComparison() }
        else { super.keyUp(with: event) }
    }
    var navigate: ((Int) -> Void)?
    var showInfo: (() -> Void)?
    var edit: ((ImageEdit) -> Void)?
    var viewChanged: (() -> Void)?
    var dropFile: ((URL) -> Void)?
    var image: NSImage? { didSet { needsDisplay = true } }
    var message = "Otevřete obrázek" { didSet { needsDisplay = true } }
    private var scrollTotal: CGFloat = 0
    private var lastNavigation: TimeInterval = 0
    private var lastScroll: TimeInterval = 0
    private var zoomScrollGesture = false
    private let preferences = ViewerPreferences()
    private(set) var fitToScreen = true
    private var manualScale: CGFloat = 1
    private var pan = CGPoint.zero
    private(set) var cropping = false
    private var selection: CGRect?
    private var dragStart: CGPoint?
    private var panStart = CGPoint.zero

    var displayScale: CGFloat {
        guard let image = displayedImage, image.size.width > 0, image.size.height > 0 else { return 1 }
        return fitToScreen ? min(max(1, bounds.width - 24) / image.size.width,
                                 max(1, bounds.height - 24) / image.size.height) : manualScale
    }

    private var imageRect: CGRect {
        guard let image = displayedImage else { return .zero }
        let size = CGSize(width: image.size.width * displayScale, height: image.size.height * displayScale)
        let maxX = max(0, (size.width - bounds.width + 24) / 2)
        let maxY = max(0, (size.height - bounds.height + 24) / 2)
        return CGRect(x: bounds.midX - size.width / 2 + min(maxX, max(-maxX, pan.x)),
                      y: bounds.midY - size.height / 2 + min(maxY, max(-maxY, pan.y)), width: size.width, height: size.height)
    }

    func setFit(_ enabled: Bool, remember: Bool = true) {
        fitToScreen = enabled
        if remember { preferences.fitImagesToWindow = enabled }
        manualScale = 1
        pan = .zero
        cancelCrop()
        needsDisplay = true
        viewChanged?()
    }

    func zoom(by factor: CGFloat) {
        guard image != nil else { return }
        manualScale = min(16, max(0.02, displayScale * factor))
        fitToScreen = false
        cancelCrop()
        needsDisplay = true
        viewChanged?()
    }

    func actualSize() { setFit(false, remember: false) }
    func resetViewport() {
        // Restore the explicit checkbox preference; temporary zoom is not saved.
        fitToScreen = preferences.fitImagesToWindow
        manualScale = 1
        pan = .zero
        cancelCrop()
        needsDisplay = true
        viewChanged?()
    }

    func beginCrop() {
        guard image != nil else { return }
        cropping = true
        selection = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func cancelCrop() {
        cropping = false
        selection = nil
        dragStart = nil
        needsDisplay = true
    }

    func confirmCrop() {
        guard cropping, let selection, selection.width >= 3, selection.height >= 3 else { NSSound.beep(); return }
        let rect = imageRect
        let normalized = CGRect(x: (selection.minX - rect.minX) / rect.width,
                                y: (rect.maxY - selection.maxY) / rect.height,
                                width: selection.width / rect.width, height: selection.height / rect.height)
        cancelCrop()
        edit?(.crop(normalized))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cancelCrop()
        needsDisplay = true
        viewChanged?()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fitToScreen = preferences.fitImagesToWindow
        wantsLayer = true
        layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard image != nil, imageRect.contains(point) else { return }
        dragStart = point
        panStart = pan
        if cropping { selection = nil }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        if cropping {
            selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                               width: abs(point.x - start.x), height: abs(point.y - start.y))
                .intersection(imageRect).intersection(bounds)
        } else if !fitToScreen {
            pan = CGPoint(x: panStart.x + point.x - start.x, y: panStart.y + point.y - start.y)
            // Keep stored pan in the same range as the displayed pan.
            let rect = imageRect
            pan = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil }
    override func magnify(with event: NSEvent) { zoom(by: max(0.1, 1 + event.magnification)) }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Clip explicitly as well as at the layer boundary. At manual zoom the
        // image can extend outside its viewport, but never over the status bar.
        NSBezierPath(rect: bounds).addClip()
        NSColor(calibratedWhite: 0.075, alpha: 1).setFill()
        bounds.fill()
        guard let image = displayedImage else {
            let title = NSAttributedString(string: message, attributes: [
                .font: NSFont.systemFont(ofSize: 21, weight: .medium), .foregroundColor: NSColor.white
            ])
            let subtitle = NSAttributedString(string: "⌘O otevřít  ·  ← → procházet  ·  F celá obrazovka  ·  I informace", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.lightGray
            ])
            title.draw(at: NSPoint(x: max(20, (bounds.width - title.size().width) / 2), y: bounds.midY + 12))
            subtitle.draw(at: NSPoint(x: max(20, (bounds.width - subtitle.size().width) / 2), y: bounds.midY - 22))
            return
        }
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        if isComparing {
            NSAttributedString(string: "Originál · uvolněte B pro návrat", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black]).draw(at: CGPoint(x: 16, y: bounds.height - 32))
        }
        if cropping {
            if let selection, !selection.isEmpty {
                let shade = NSBezierPath(rect: bounds)
                shade.append(NSBezierPath(rect: selection))
                shade.windingRule = .evenOdd
                NSColor.black.withAlphaComponent(0.55).setFill()
                shade.fill()
                NSColor.white.setStroke()
                let border = NSBezierPath(rect: selection)
                border.lineWidth = 1.5
                border.stroke()
            }
            let hint = NSAttributedString(string: "Výřez: tažením vyberte oblast · Enter potvrdit · Esc zrušit", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.8)
            ])
            hint.draw(at: CGPoint(x: 16, y: bounds.height - 32))
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event); return
        }
        if event.charactersIgnoringModifiers?.lowercased() == "b", !cropping, originalImage != nil {
            isComparing = true; needsDisplay = true; viewChanged?(); return
        }
        if isComparing { return }
        if cropping {
            if event.keyCode == 53 { cancelCrop() }
            else if event.keyCode == 36 || event.keyCode == 76 { confirmCrop() }
            return
        }
        switch event.keyCode {
        case 123, 126: navigate?(-1)
        case 124, 125: navigate?(1)
        case 53:
            stopSlideshow?()
            if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": window?.toggleFullScreen(nil)
            case "i": showInfo?()
            case "+", "=": zoom(by: 1.25)
            case "-": zoom(by: 0.8)
            case " ": navigate?(1)
            default: super.keyDown(with: event)
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Latch the gesture so releasing Command cannot turn its remaining events
        // (or momentum) into navigation to another file.
        if event.phase == .began || event.timestamp - lastScroll > 0.3 {
            zoomScrollGesture = false
        }
        if event.modifierFlags.contains(.command) { zoomScrollGesture = true }
        if zoomScrollGesture {
            lastScroll = event.timestamp
            scrollTotal = 0
            guard event.momentumPhase.isEmpty else { return }
            let delta = event.scrollingDeltaY
            if delta != 0 {
                zoom(by: exp(delta * (event.hasPreciseScrollingDeltas ? 0.008 : 0.12)))
            }
            return
        }
        guard event.momentumPhase.isEmpty else { return }
        let now = event.timestamp
        if now - lastScroll > 0.2 || event.phase == .began { scrollTotal = 0 }
        lastScroll = now
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard delta != 0, now - lastNavigation > 0.22 else { return }
        scrollTotal += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 35 : 1
        if abs(scrollTotal) >= threshold {
            navigate?(scrollTotal < 0 ? 1 : -1)
            scrollTotal = 0
            lastNavigation = now
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first else { return false }
        dropFile?(url)
        return true
    }
}
