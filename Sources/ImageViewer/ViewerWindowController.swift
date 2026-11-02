import AppKit
import ViewerCore

final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let canvas = ImageCanvas()
    private let gallery = GalleryView()
    private let galleryButton = NSButton(title: "Galerie", target: nil, action: nil)
    private var galleryVisible = false
    private var detailControls: [NSControl] = []
    private let infoScroll = NSScrollView()
    private let infoPanel = NSView()
    private let copyExifButton = NSButton(title: "Kopírovat EXIF jako JSON", target: nil, action: nil)
    private var currentMetadata: LoadedImage?
    private let infoText = NSTextView()
    private let status = NSTextField(labelWithString: "Otevřete obrázek pomocí ⌘O nebo jej přetáhněte do okna")
    private let previous = NSButton()
    private let next = NSButton()
    private let fitCheckbox = NSButton(checkboxWithTitle: "Přizpůsobit oknu", target: nil, action: nil)
    private let zoomLabel = NSTextField(labelWithString: "100 %")
    private let imageDetails = NSTextField(labelWithString: "")
    private var currentSize: CGSize?
    private let queue = OperationQueue()
    private let cache = NSCache<NSURL, LoadedImage>()
    private var files: [URL] = []
    private var index = 0
    private var generation = UUID()
    private var infoVisible = false
    private let preferences = ViewerPreferences()
    private var edits: [URL: [ImageEdit]] = [:]
    private var exporting = false
    private var savedEdits: [URL: [ImageEdit]] = [:]
    private var leavePromptVisible = false
    private var closingApproved = false
    private var slideTimer: Timer?
    private var slideshowEnteredFullscreen = false
    private let gallerySize = NSSlider(value: 200, minValue: 130, maxValue: 340, target: nil, action: nil)
    private let selectionToggle = NSButton(checkboxWithTitle: "Výběr více", target: nil, action: nil)
    private let batchButton = NSButton(title: "Exportovat vybrané…", target: nil, action: nil)
    private var trashHistory: [(original: URL, trashed: URL, edits: [ImageEdit], saved: [ImageEdit]?)] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        infoVisible = preferences.showImageInformation
        window.title = "Image Viewer"
        window.minSize = NSSize(width: 800, height: 420)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        cache.totalCostLimit = 192 * 1024 * 1024
        buildContent()
        canvas.navigate = { [weak self] in self?.navigate($0) }
        canvas.showInfo = { [weak self] in self?.toggleInfo() }
        canvas.dropFile = { [weak self] in self?.open($0) }
        canvas.edit = { [weak self] in self?.performEdit($0) }
        canvas.viewChanged = { [weak self] in self?.updateViewControls() }
        gallery.selectImage = { [weak self] selected in
            guard let self, self.files.indices.contains(selected) else { return }
            self.index = selected
            self.setGalleryVisible(false)
            self.displayCurrent()
        }
        canvas.stopSlideshow = { [weak self] in self?.stopSlideshow() }
        gallery.selectionChanged = { [weak self] in self?.updateGallerySelection() }
        gallery.contextAction = { [weak self] action in
            switch action {
            case "finder": self?.revealInFinder()
            case "path": self?.copyFilePath()
            case "export": self?.exportSelected()
            default: break
            }
        }
        gallery.closeGallery = { [weak self] in self?.setGalleryVisible(false) }
        window.makeFirstResponder(canvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let open = button("folder", label: "Otevřít obrázek (⌘O)", action: #selector(chooseFile))
        previous.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Předchozí obrázek")
        previous.target = self; previous.action = #selector(goPrevious); previous.bezelStyle = .texturedRounded
        previous.toolTip = "Předchozí obrázek (←)"
        next.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Další obrázek")
        next.target = self; next.action = #selector(goNext); next.bezelStyle = .texturedRounded
        next.toolTip = "Další obrázek (→)"
        let info = button("info.circle", label: "Informace a EXIF (I)", action: #selector(toggleInfo))
        let fullscreen = button("arrow.up.left.and.arrow.down.right", label: "Celá obrazovka (F)", action: #selector(fullscreen))
        let zoomOut = button("minus.magnifyingglass", label: "Oddálit (−)", action: #selector(ViewerWindowController.zoomOut))
        let zoomIn = button("plus.magnifyingglass", label: "Přiblížit (+)", action: #selector(ViewerWindowController.zoomIn))
        galleryButton.target = self
        galleryButton.action = #selector(toggleGallery)
        galleryButton.bezelStyle = .texturedRounded
        galleryButton.setButtonType(.pushOnPushOff)
        galleryButton.toolTip = "Náhledy všech obrázků ve složce (⌘G)"
        detailControls = [zoomOut, zoomIn, fitCheckbox, info]
        fitCheckbox.target = self
        fitCheckbox.action = #selector(changeFit)
        fitCheckbox.toolTip = "Zobrazit celý obrázek podle velikosti okna; vypnutím přejdete na 100 %."
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.alignment = .right
        zoomLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        imageDetails.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        imageDetails.textColor = .secondaryLabelColor
        imageDetails.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageDetails.setAccessibilityLabel("Rozměry obrázku a typ souboru")
        gallerySize.target = self; gallerySize.action = #selector(changeGallerySize)
        gallerySize.toolTip = "Velikost náhledů galerie"
        gallerySize.doubleValue = preferences.galleryThumbnailSize
        gallerySize.widthAnchor.constraint(equalToConstant: 110).isActive = true
        selectionToggle.target = self; selectionToggle.action = #selector(changeSelectionMode)
        batchButton.target = self; batchButton.action = #selector(exportSelected)
        for control in [gallerySize, selectionToggle, batchButton] { control.isHidden = true }
        let spacer = NSView()
        let bar = NSStackView(views: [open, galleryButton, previous, next, status, spacer, gallerySize, selectionToggle, batchButton, imageDetails, zoomOut, zoomLabel, zoomIn, fitCheckbox, info, fullscreen])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        infoText.isEditable = false
        infoText.isSelectable = true
        infoText.font = .systemFont(ofSize: 12)
        infoText.textContainerInset = NSSize(width: 14, height: 16)
        infoText.autoresizingMask = [.width]
        infoText.isVerticallyResizable = true
        infoText.isHorizontallyResizable = false
        infoText.textContainer?.widthTracksTextView = true
        infoText.string = "Informace se zobrazí po otevření obrázku."
        infoScroll.documentView = infoText
        infoScroll.hasVerticalScroller = true
        copyExifButton.target = self
        copyExifButton.action = #selector(copyExifJSON)
        copyExifButton.bezelStyle = .rounded
        copyExifButton.toolTip = "Zkopírovat EXIF a všechna dostupná metadata původního souboru jako JSON (⌘⇧C)"
        copyExifButton.isEnabled = false
        for view in [copyExifButton, infoScroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            infoPanel.addSubview(view)
        }
        let copyButtonTrailing = copyExifButton.trailingAnchor.constraint(lessThanOrEqualTo: infoPanel.trailingAnchor, constant: -12)
        copyButtonTrailing.priority = .defaultHigh
        copyExifButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            copyExifButton.topAnchor.constraint(equalTo: infoPanel.topAnchor, constant: 12),
            copyExifButton.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 12),
            copyButtonTrailing,
            infoScroll.topAnchor.constraint(equalTo: copyExifButton.bottomAnchor, constant: 8),
            infoScroll.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor),
            infoScroll.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor),
            infoScroll.bottomAnchor.constraint(equalTo: infoPanel.bottomAnchor)
        ])
        infoPanel.isHidden = !infoVisible
        gallery.isHidden = true
        for view in [canvas, infoPanel, gallery, bar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        infoWidth = infoPanel.widthAnchor.constraint(equalToConstant: infoVisible ? 310 : 0)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor), bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor), bar.heightAnchor.constraint(equalToConstant: 46),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor), canvas.topAnchor.constraint(equalTo: content.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor), canvas.trailingAnchor.constraint(equalTo: infoPanel.leadingAnchor),
            gallery.leadingAnchor.constraint(equalTo: content.leadingAnchor), gallery.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            gallery.topAnchor.constraint(equalTo: content.topAnchor), gallery.bottomAnchor.constraint(equalTo: bar.topAnchor),
            infoPanel.trailingAnchor.constraint(equalTo: content.trailingAnchor), infoPanel.topAnchor.constraint(equalTo: content.topAnchor),
            infoPanel.bottomAnchor.constraint(equalTo: bar.topAnchor), infoWidth!
        ])
        updateButtons()
        updateViewControls()
    }
    private var infoWidth: NSLayoutConstraint?

    @objc func toggleGallery() {
        guard !files.isEmpty, !exporting else { return }
        setGalleryVisible(!galleryVisible)
    }

    private func setGalleryVisible(_ visible: Bool) {
        if visible { stopSlideshow() }
        galleryVisible = visible
        galleryButton.state = visible ? .on : .off
        gallery.isHidden = !visible
        canvas.isHidden = visible
        infoPanel.isHidden = visible || !infoVisible
        infoWidth?.constant = !visible && infoVisible ? 310 : 0
        imageDetails.isHidden = visible
        zoomLabel.isHidden = visible
        for control in detailControls { control.isHidden = visible }
        for control in [gallerySize, selectionToggle, batchButton] { control.isHidden = !visible }
        updateButtons()
        if visible {
            canvas.cancelCrop()
            gallery.setThumbnailSize(gallerySize.doubleValue)
            gallery.show(files: files, currentIndex: index)
            gallery.setSelectionMode(selectionToggle.state == .on)
            gallery.focus()
            updateGallerySelection()
        } else {
            gallery.suspend()
            window?.makeFirstResponder(canvas)
            if files.indices.contains(index) {
                status.stringValue = "\(index + 1) / \(files.count)  ·  \(files[index].lastPathComponent)"
                if edits[files[index]]?.isEmpty == false { status.stringValue += "  ·  upraveno" }
            }
        }
    }

    @objc func saveAs() {
        guard !exporting, canvas.image != nil, !canvas.cropping, files.indices.contains(index), let window else { return }
        let source = files[index]
        let history = edits[source] ?? []
        let panel = NSSavePanel()
        panel.title = "Uložit aktuální podobu obrázku"
        panel.prompt = "Uložit"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "-upraveno.png"
        let options = ExportOptionsView(panel: panel)
        panel.accessoryView = options
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            let format = options.format
            let settings = options.settings
            self.exporting = true
            let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
                                   styleMask: [.titled], backing: .buffered, defer: false)
            progress.title = "Ukládání obrázku"
            let spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 30, width: 24, height: 24))
            spinner.style = .spinning
            spinner.startAnimation(nil)
            let label = NSTextField(labelWithString: "Ukládám upravený obrázek…")
            label.frame = NSRect(x: 64, y: 32, width: 280, height: 20)
            progress.contentView?.addSubview(spinner)
            progress.contentView?.addSubview(label)
            window.beginSheet(progress)
            self.queue.cancelAllOperations()
            let previewQueue = self.queue
            // Independent of the preview queue, whose operations are cancelled on navigation.
            DispatchQueue.global(qos: .userInitiated).async {
                // Finish any in-flight preload before a possible source replacement,
                // so it cannot restore an obsolete bitmap to the preview cache.
                previewQueue.waitUntilAllOperationsAreFinished()
                let result = Result { try ImageExporter.write(source: source, edits: history, to: destination, format: format, settings: settings) }
                DispatchQueue.main.async {
                    window.endSheet(progress)
                    progress.orderOut(nil)
                    self.exporting = false
                    switch result {
                    case .success:
                        if self.edits[source] == history { self.savedEdits[source] = history }
                        self.didExport(source: source, destination: destination)
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "Obrázek se nepodařilo uložit"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.beginSheetModal(for: window)
                    }
                }
            }
        }
    }

    private func didExport(source: URL, destination: URL) {
        gallery.invalidateThumbnails()
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL
        // Invalidate edited previews if an existing file was explicitly replaced.
        for url in files where url.resolvingSymlinksInPath().standardizedFileURL == destinationPath {
            cache.removeObject(forKey: url as NSURL)
            edits[url] = nil
            savedEdits[url] = nil
        }
        guard files.indices.contains(index) else { return }
        let current = files[index]
        if let refreshed = try? ImageFolder.images(beside: current), let position = refreshed.firstIndex(of: current) {
            files = refreshed
            index = position
            updateButtons()
        }
        if current.resolvingSymlinksInPath().standardizedFileURL == destinationPath {
            // Reload the saved file without applying the same edits a second time.
            displayCurrent()
        } else if current == source {
            status.stringValue = "\(index + 1) / \(files.count)  ·  \(current.lastPathComponent)  ·  Uloženo: \(destination.lastPathComponent)"
            status.toolTip = destination.path
        }
    }

    @objc func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageFolder.supportedTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.open(url) }
        }
    }

    func open(_ url: URL) {
        guard url.isFileURL else { return }
        stopSlideshow()
        prepareToLeave { [weak self] allowed in
            if allowed { self?.openConfirmed(url) }
        }
    }

    private func openConfirmed(_ url: URL) {
        setGalleryVisible(false)
        gallery.invalidateThumbnails()
        queue.cancelAllOperations()
        cache.removeAllObjects()
        let token = UUID()
        generation = token
        files = []
        edits.removeAll()
        savedEdits.removeAll()
        canvas.resetViewport()
        canvas.image = nil
        canvas.originalImage = nil
        canvas.endComparison()
        currentMetadata = nil
        copyExifButton.isEnabled = false
        copyExifButton.title = "Kopírovat EXIF jako JSON"
        currentSize = nil
        imageDetails.stringValue = ""
        canvas.message = "Načítání…"
        infoText.string = "Načítání…"
        status.stringValue = url.lastPathComponent
        window?.title = url.lastPathComponent
        window?.representedURL = url
        updateButtons()
        queue.addOperation { [weak self] in
            do {
                var files = try ImageFolder.images(beside: url)
                if !files.contains(url) { files.append(url) }
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.files = files
                    self.index = files.firstIndex(of: url) ?? 0
                    self.displayCurrent()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    // The requested file can still be displayed if the parent cannot be listed.
                    self.files = [url]
                    self.index = 0
                    self.displayCurrent(folderWarning: "Složku nelze procházet: \(error.localizedDescription)")
                }
            }
        }
    }

    private func displayCurrent(folderWarning: String? = nil, resetViewport: Bool = true) {
        guard files.indices.contains(index) else { return }
        queue.cancelAllOperations()
        let token = UUID()
        generation = token
        let url = files[index]
        if resetViewport { canvas.resetViewport() }
        window?.title = url.lastPathComponent
        window?.representedURL = url
        status.stringValue = "\(index + 1) / \(files.count)  ·  \(url.lastPathComponent)"
        status.toolTip = folderWarning ?? url.path
        canvas.image = nil
        canvas.originalImage = nil
        canvas.endComparison()
        currentMetadata = nil
        copyExifButton.isEnabled = false
        copyExifButton.title = "Kopírovat EXIF jako JSON"
        currentSize = nil
        imageDetails.stringValue = ""
        canvas.message = "Načítání…"
        infoText.string = "Načítání…"
        updateButtons()
        if !galleryVisible { window?.makeFirstResponder(canvas) }
        let history = edits[url] ?? []
        let cache = self.cache
        queue.addOperation { [weak self] in
            let result = Result { () throws -> (LoadedImage, EditableImage) in
                let loaded = try cache.object(forKey: url as NSURL) ?? LoadedImage(url: url)
                cache.setObject(loaded, forKey: url as NSURL, cost: loaded.cost)
                var edited = EditableImage(bitmap: loaded.bitmap, size: loaded.size)
                for operation in history {
                    guard let next = autoreleasepool(invoking: { edited.applying(operation, maxPixelSize: 6000) }) else {
                        throw NSError(domain: "ImageViewer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Úpravu obrázku se nepodařilo provést."])
                    }
                    edited = next
                }
                return (loaded, edited)
            }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let (loaded, edited)):
                    self.currentMetadata = loaded
                    self.copyExifButton.isEnabled = true
                    self.canvas.originalImage = NSImage(cgImage: loaded.bitmap, size: loaded.size)
                    self.canvas.image = NSImage(cgImage: edited.bitmap, size: edited.size)
                    self.currentSize = edited.size
                    self.imageDetails.stringValue = "\(Int(edited.size.width)) × \(Int(edited.size.height)) px · \(loaded.fileType)"
                    self.imageDetails.toolTip = "Aktuální rozměry po úpravách. Typ původního souboru: \(loaded.fileType)."
                    let note = history.isEmpty ? "" : "\n\nNáhled obsahuje \(history.count) úprav v paměti. Metadata výše patří původnímu souboru."
                    self.infoText.string = loaded.details + note + (folderWarning.map { "\n\n\($0)" } ?? "")
                    if !history.isEmpty && !self.galleryVisible { self.status.stringValue += "  ·  upraveno" }
                    self.updateViewControls()
                    self.preloadNeighbors()
                case .failure(let error):
                    self.canvas.message = "Obrázek nelze zobrazit"
                    self.infoText.string = "\(url.lastPathComponent)\n\n\(error.localizedDescription)"
                    if !self.galleryVisible { self.status.stringValue += "  ·  Nelze načíst; pokračujte šipkou" }
                }
            }
        }
    }

    private func preloadNeighbors() {
        let cache = self.cache
        for position in [index + 1, index - 1] where files.indices.contains(position) {
            let url = files[position]
            guard cache.object(forKey: url as NSURL) == nil else { continue }
            queue.addOperation {
                if let loaded = try? LoadedImage(url: url) {
                    cache.setObject(loaded, forKey: url as NSURL, cost: loaded.cost)
                }
            }
        }
    }

    private func navigate(_ step: Int) {
        guard !galleryVisible, let target = ImageFolder.nextIndex(current: index, step: step, count: files.count), target != index else { return }
        index = target
        displayCurrent()
    }
    private func updateButtons() {
        previous.isEnabled = !galleryVisible && files.count > 1
        next.isEnabled = !galleryVisible && files.count > 1
        galleryButton.isEnabled = !files.isEmpty
    }
    private func updateViewControls() {
        fitCheckbox.state = canvas.fitToScreen ? .on : .off
        zoomLabel.stringValue = "\(Int((canvas.displayScale * 100).rounded())) %"
    }

    private func performEdit(_ edit: ImageEdit) {
        guard !exporting, !canvas.isComparing, canvas.image != nil, files.indices.contains(index) else { return }
        stopSlideshow()
        canvas.cancelCrop()
        edits[files[index], default: []].append(edit)
        displayCurrent(resetViewport: false)
    }

    @objc func rotateLeft() { performEdit(.rotateLeft) }
    @objc func rotateRight() { performEdit(.rotateRight) }
    @objc func flipHorizontal() { performEdit(.flipHorizontal) }
    @objc func flipVertical() { performEdit(.flipVertical) }
    @objc func beginCrop() { canvas.beginCrop() }
    @objc func resizeImage() {
        guard let size = currentSize, canvas.image != nil, !canvas.cropping, let window else { return }
        let token = generation
        let alert = NSAlert()
        alert.messageText = "Změnit rozměry obrázku"
        alert.informativeText = "Zadejte novou šířku a výšku v pixelech. Změna se použije také při uložení obrázku."
        let confirm = alert.addButton(withTitle: "Změnit rozměry")
        alert.addButton(withTitle: "Zrušit")
        let options = ResizeOptionsView(size: size, confirmButton: confirm)
        alert.accessoryView = options
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.generation == token, response == .alertFirstButtonReturn,
                  let dimensions = options.dimensions else { return }
            self.performEdit(.resize(width: dimensions.width, height: dimensions.height))
        }
    }
    @objc func confirmCrop() { canvas.confirmCrop() }
    @objc func cancelCrop() { canvas.cancelCrop() }
    @objc func resetEdits() {
        guard files.indices.contains(index) else { return }
        edits[files[index]] = nil
        displayCurrent()
    }
    @objc func undoEdit() {
        guard files.indices.contains(index), edits[files[index]]?.isEmpty == false else { return }
        edits[files[index]]?.removeLast()
        displayCurrent(resetViewport: false)
    }
    @objc func zoomIn() { canvas.zoom(by: 1.25); window?.makeFirstResponder(canvas) }
    @objc func zoomOut() { canvas.zoom(by: 0.8); window?.makeFirstResponder(canvas) }
    @objc func actualSize() { canvas.actualSize(); window?.makeFirstResponder(canvas) }
    @objc private func changeFit() { canvas.setFit(fitCheckbox.state == .on); window?.makeFirstResponder(canvas) }
    @objc func toggleFit() { canvas.setFit(!canvas.fitToScreen); window?.makeFirstResponder(canvas) }

    @objc func copyExifJSON() {
        guard !galleryVisible, let currentMetadata else { return }
        do {
            let json = try currentMetadata.metadataJSON()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(json, forType: .string) else {
                throw NSError(domain: "ImageViewer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Nelze zapsat do schránky."])
            }
            copyExifButton.title = "Zkopírováno ✓"
            let token = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.generation == token else { return }
                self.copyExifButton.title = "Kopírovat EXIF jako JSON"
            }
        } catch {
            guard let window else { return }
            let alert = NSAlert()
            alert.messageText = "Metadata se nepodařilo zkopírovat"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleGallery) {
            menuItem.state = galleryVisible ? .on : .off
            return !files.isEmpty && !exporting
        }
        if menuItem.action == #selector(revealInFinder) || menuItem.action == #selector(copyFilePath) { return !files.isEmpty }
        if menuItem.action == #selector(exportSelected) { return galleryVisible && !gallery.selectedIndices.isEmpty && !exporting }
        if menuItem.action == #selector(restoreFromTrash) { return !trashHistory.isEmpty && !exporting }
        if menuItem.action == #selector(startSlideshow) { return files.count > 1 && !exporting }
        if menuItem.action == #selector(stopSlideshow) { return slideTimer != nil }
        if galleryVisible || exporting || canvas.isComparing { return false }
        if menuItem.action == #selector(copyExifJSON) { return currentMetadata != nil }
        if menuItem.action == #selector(resizeImage) {
            return !exporting && currentSize != nil && canvas.image != nil && !canvas.cropping
        }
        if menuItem.action == #selector(saveAs) {
            return !exporting && canvas.image != nil && !canvas.cropping
        }
        if menuItem.action == #selector(toggleFit) {
            menuItem.state = canvas.fitToScreen ? .on : .off
            return true
        }
        if menuItem.action == #selector(undoEdit) || menuItem.action == #selector(resetEdits) {
            return files.indices.contains(index) && edits[files[index]]?.isEmpty == false
        }
        if menuItem.action == #selector(confirmCrop) || menuItem.action == #selector(cancelCrop) {
            return canvas.cropping
        }
        return canvas.image != nil
    }
    @objc private func goPrevious() { navigate(-1) }
    @objc private func goNext() { navigate(1) }
    @objc private func fullscreen() { window?.toggleFullScreen(nil) }
    @objc func toggleInfo() {
        infoVisible.toggle()
        preferences.showImageInformation = infoVisible
        infoPanel.isHidden = !infoVisible
        infoWidth?.constant = infoVisible ? 310 : 0
        window?.makeFirstResponder(canvas)
    }
}
