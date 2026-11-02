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
    private let quickQueue = OperationQueue()
    private let preloadQueue = OperationQueue()
    private let folderQueue = OperationQueue()
    private var folderGeneration = UUID()
    private var scanningFolder = false
    private var folderReadWarning: String?
    private var refiningImage = false
    private let cache = NSCache<NSURL, LoadedImage>()
    private var files: [URL] = []
    private var index = 0
    private var generation = UUID()
    private var infoVisible = false
    private let preferences = ViewerPreferences()
    private var edits: [URL: [ImageEdit]] = [:]
    private var loadingImage = false
    private var exporting = false
    private var savedEdits: [URL: [ImageEdit]] = [:]
    private var leavePromptVisible = false
    private var closingApproved = false
    private var slideTimer: Timer?
    private var slideshowEnteredFullscreen = false
    private let gallerySize = NSSlider(value: 200, minValue: 130, maxValue: 340, target: nil, action: nil)
    private let selectionToggle = NSButton(checkboxWithTitle: "Výběr více", target: nil, action: nil)
    private let selectAllButton = NSButton(title: "Vybrat vše", target: nil, action: nil)
    private let batchButton = NSButton(title: "Operace…", target: nil, action: nil)
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
        quickQueue.maxConcurrentOperationCount = 1
        quickQueue.qualityOfService = .userInitiated
        preloadQueue.maxConcurrentOperationCount = 1
        preloadQueue.qualityOfService = .utility
        folderQueue.maxConcurrentOperationCount = 1
        folderQueue.qualityOfService = .utility
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
        canvas.revealFile = { [weak self] in self?.revealInFinder() }
        canvas.copyPath = { [weak self] in self?.copyFilePath() }
        canvas.trashFile = { [weak self] in self?.trashCurrent() }
        canvas.stopSlideshow = { [weak self] in
            let exits = self?.slideshowEnteredFullscreen == true && self?.window?.styleMask.contains(.fullScreen) == true
            self?.stopSlideshow()
            return exits
        }
        gallery.selectionChanged = { [weak self] in self?.updateGallerySelection() }
        gallery.contextAction = { [weak self] action in
            switch action {
            case "finder": self?.revealInFinder()
            case "path": self?.copyFilePath()
            case "export": self?.exportSelected()
            case "selectAll": self?.selectAllGallery()
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
        gallerySize.widthAnchor.constraint(equalToConstant: 90).isActive = true
        selectionToggle.target = self; selectionToggle.action = #selector(changeSelectionMode)
        selectAllButton.target = self; selectAllButton.action = #selector(selectAllGallery)
        batchButton.toolTip = "Změna rozměrů, rotace a formátu vybraných obrázků"
        batchButton.target = self; batchButton.action = #selector(exportSelected)
        for control in [gallerySize, selectionToggle, selectAllButton, batchButton] { control.isHidden = true }
        let spacer = NSView()
        let bar = NSStackView(views: [open, galleryButton, previous, next, status, spacer, gallerySize, selectionToggle, selectAllButton, batchButton, imageDetails, zoomOut, zoomLabel, zoomIn, fitCheckbox, info, fullscreen])
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
        previous.isHidden = visible; next.isHidden = visible
        gallery.isHidden = !visible
        canvas.isHidden = visible
        infoPanel.isHidden = visible || !infoVisible
        infoWidth?.constant = !visible && infoVisible ? 310 : 0
        imageDetails.isHidden = visible
        zoomLabel.isHidden = visible
        for control in detailControls { control.isHidden = visible }
        for control in [gallerySize, selectionToggle, selectAllButton, batchButton] { control.isHidden = !visible }
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
        stopSlideshow()
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
            panel.orderOut(nil)
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
            self.cancelPreviewWork()
            let previewQueue = self.queue
            let fastQueue = self.quickQueue, neighborQueue = self.preloadQueue
            // Independent of the preview queue, whose operations are cancelled on navigation.
            DispatchQueue.global(qos: .userInitiated).async {
                // Finish any in-flight preload before a possible source replacement,
                // so it cannot restore an obsolete bitmap to the preview cache.
                previewQueue.waitUntilAllOperationsAreFinished()
                fastQueue.waitUntilAllOperationsAreFinished()
                neighborQueue.waitUntilAllOperationsAreFinished()
                let result = Result { try ImageExporter.write(source: source, edits: history, to: destination, format: format, settings: settings) }
                DispatchQueue.main.async {
                    window.endSheet(progress)
                    progress.orderOut(nil)
                    self.exporting = false
                    self.updateViewControls()
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
        let destinationPath = ImageFolder.canonicalURL(destination)
        // Invalidate edited previews if an existing file was explicitly replaced.
        for url in files where ImageFolder.canonicalURL(url) == destinationPath {
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
        if ImageFolder.canonicalURL(current) == destinationPath {
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
            guard response == .OK, let url = panel.url else { panel.orderOut(nil); return }
            self?.openSelectedFile(url, dismissing: panel)
        }
    }

    private func openSelectedFile(_ url: URL, dismissing panel: NSWindow) {
        // The completion can run while the panel is still an attached sheet.
        // Detach it before asking the unsaved-changes guard to open another file.
        panel.orderOut(nil)
        DispatchQueue.main.async { [weak self] in self?.open(url) }
    }

    func open(_ url: URL) {
        guard url.isFileURL else { return }
        let url = ImageFolder.canonicalURL(url)
        stopSlideshow()
        prepareToLeave { [weak self] allowed in
            if allowed { self?.openConfirmed(url) }
        }
    }

    private func openConfirmed(_ url: URL) {
        setGalleryVisible(false)
        gallery.invalidateThumbnails()
        cancelPreviewWork()
        folderQueue.cancelAllOperations()
        cache.removeAllObjects()
        edits.removeAll(); savedEdits.removeAll()
        folderReadWarning = nil
        files = [url]; index = 0
        let folderToken = UUID()
        folderGeneration = folderToken
        scanningFolder = true
        // Display the chosen file immediately; listing a large or remote folder
        // must not postpone the first visible preview.
        displayCurrent()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let result = Result { try ImageFolder.images(beside: url) }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async { [weak self, operation] in
                guard let self, self.folderGeneration == folderToken, operation?.isCancelled == false else { return }
                self.scanningFolder = false
                switch result {
                case .success(var images):
                    if !images.contains(url) { images.append(url) }
                    let current = self.files.indices.contains(self.index) ? self.files[self.index] : url
                    let selection = Set(self.gallery.selectedIndices.filter { self.files.indices.contains($0) }.map { self.files[$0] })
                    self.files = images
                    self.index = images.firstIndex(of: current) ?? images.firstIndex(of: url) ?? 0
                    if self.galleryVisible {
                        self.gallery.show(files: images, currentIndex: self.index)
                        self.gallery.selectImages(at: images.indices.filter { selection.contains(images[$0]) })
                        self.updateGallerySelection()
                    } else {
                        self.status.stringValue = "\(self.index + 1) / \(images.count)  ·  \(current.lastPathComponent)"
                        if self.edits[current]?.isEmpty == false { self.status.stringValue += "  ·  upraveno" }
                    }
                    if !self.refiningImage, self.canvas.image != nil { self.preloadNeighbors() }
                case .failure(let error):
                    let warning = "Složku nelze procházet: \(error.localizedDescription)"
                    self.folderReadWarning = warning
                    self.status.toolTip = warning
                    if self.currentMetadata != nil { self.infoText.string += "\n\n" + warning }
                }
                self.updateButtons()
            }
        }
        folderQueue.addOperation(operation)
    }

    private var desiredPreviewPixels: Int {
        PreviewSizing.pixelLimit(viewport: canvas.bounds.size, backingScale: window?.backingScaleFactor ?? 2,
                                 fitToWindow: canvas.fitToScreen)
    }

    private func cancelPreviewWork() {
        refiningImage = false
        queue.cancelAllOperations()
        quickQueue.cancelAllOperations()
        preloadQueue.cancelAllOperations()
    }

    private func displayCurrent(folderWarning: String? = nil, resetViewport: Bool = true, keepVisible: Bool = false) {
        guard files.indices.contains(index) else { return }
        cancelPreviewWork()
        let token = UUID()
        generation = token
        let url = files[index]
        if resetViewport { canvas.resetViewport() }
        let requested = desiredPreviewPixels
        refiningImage = true
        window?.title = url.lastPathComponent
        window?.representedURL = url
        status.stringValue = "\(index + 1) / \(files.count)  ·  \(url.lastPathComponent)"
        status.toolTip = folderWarning ?? url.path
        if !keepVisible {
            canvas.image = nil; canvas.originalImage = nil; canvas.endComparison()
            currentMetadata = nil; currentSize = nil
            copyExifButton.isEnabled = false; copyExifButton.title = "Kopírovat EXIF jako JSON"
            imageDetails.stringValue = ""
            canvas.message = "Načítání…"; infoText.string = "Načítání…"
        }
        loadingImage = canvas.image == nil
        updateButtons()
        if !galleryVisible { window?.makeFirstResponder(canvas) }
        let history = edits[url] ?? []
        let cache = self.cache
        var finalApplied = false

        func present(_ loaded: LoadedImage, _ edited: EditableImage, final: Bool) {
            guard generation == token, final || !finalApplied else { return }
            if final { finalApplied = true; refiningImage = false }
            loadingImage = false
            if let cached = cache.object(forKey: url as NSURL) {
                if cached.decodedPixelSize < loaded.decodedPixelSize {
                    cache.setObject(loaded, forKey: url as NSURL, cost: loaded.cost)
                }
            } else { cache.setObject(loaded, forKey: url as NSURL, cost: loaded.cost) }
            currentMetadata = loaded; copyExifButton.isEnabled = true
            canvas.originalImage = NSImage(cgImage: loaded.bitmap, size: loaded.size)
            canvas.image = NSImage(cgImage: edited.bitmap, size: edited.size)
            currentSize = edited.size
            imageDetails.stringValue = "\(Int(edited.size.width)) × \(Int(edited.size.height)) px · \(loaded.fileType)"
            imageDetails.toolTip = "Aktuální rozměry po úpravách. Typ původního souboru: \(loaded.fileType)."
            let note = history.isEmpty ? "" : "\n\nNáhled obsahuje \(history.count) úprav v paměti. Metadata výše patří původnímu souboru."
            let details = loaded.details + note + ((folderWarning ?? folderReadWarning).map { "\n\n\($0)" } ?? "")
            if infoText.string != details { infoText.string = details }
            if !history.isEmpty && !galleryVisible {
                status.stringValue = "\(index + 1) / \(files.count)  ·  \(url.lastPathComponent)  ·  upraveno"
            }
            updateViewControls()
            if final { preloadNeighbors() }
        }

        func enqueue(on workQueue: OperationQueue, limit: Int, final: Bool) {
            let operation = BlockOperation()
            operation.queuePriority = final ? .high : .veryHigh
            operation.addExecutionBlock { [self, weak operation] in
                guard operation?.isCancelled == false else { return }
                let result = Result { () throws -> (LoadedImage, EditableImage) in
                    let cached = cache.object(forKey: url as NSURL)
                    let loaded: LoadedImage
                    if let cached, !final || cached.satisfies(pixelLimit: limit) { loaded = cached }
                    else { loaded = try LoadedImage(url: url, maxPixelSize: limit, preferEmbeddedThumbnail: !final) }
                    var edited = EditableImage(bitmap: loaded.bitmap, size: loaded.size)
                    for edit in history {
                        guard operation?.isCancelled == false else { throw CocoaError(.userCancelled) }
                        guard let next = autoreleasepool(invoking: { edited.applying(edit, maxPixelSize: limit) }) else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        edited = next
                    }
                    return (loaded, edited)
                }
                guard operation?.isCancelled == false else { return }
                DispatchQueue.main.async { [weak self, operation] in
                    guard let self, self.generation == token, operation?.isCancelled == false else { return }
                    switch result {
                    case .success(let (loaded, edited)): present(loaded, edited, final: final)
                    case .failure(let error):
                        guard final else { return }
                        self.refiningImage = false; self.loadingImage = false
                        if self.canvas.image == nil {
                            self.canvas.message = "Obrázek nelze zobrazit"
                            self.infoText.string = "\(url.lastPathComponent)\n\n\(error.localizedDescription)"
                            if !self.galleryVisible { self.status.stringValue += "  ·  Nelze načíst; pokračujte šipkou" }
                        } else { self.status.toolTip = error.localizedDescription }
                    }
                }
            }
            workQueue.addOperation(operation)
        }

        if let cached = cache.object(forKey: url as NSURL), history.isEmpty {
            present(cached, EditableImage(bitmap: cached.bitmap, size: cached.size), final: cached.satisfies(pixelLimit: requested))
            if finalApplied { return }
        } else if !keepVisible {
            enqueue(on: quickQueue, limit: min(1024, requested), final: false)
        }
        enqueue(on: queue, limit: requested, final: true)
    }

    private func preloadNeighbors() {
        guard !galleryVisible, !exporting else { return }
        let cache = self.cache
        let limit = desiredPreviewPixels
        var positions: [Int] = []
        for step in [1, -1] {
            if let position = ImageFolder.nextIndex(current: index, step: step, count: files.count), position != index, !positions.contains(position) {
                positions.append(position)
            }
        }
        for position in positions {
            let url = files[position]
            if cache.object(forKey: url as NSURL)?.satisfies(pixelLimit: limit) == true { continue }
            let operation = BlockOperation()
            operation.queuePriority = .low
            operation.addExecutionBlock { [weak operation] in
                guard operation?.isCancelled == false else { return }
                let loaded = try? LoadedImage(url: url, maxPixelSize: limit)
                guard operation?.isCancelled == false, let loaded else { return }
                DispatchQueue.main.async { [operation] in
                    guard operation?.isCancelled == false else { return }
                    if let cached = cache.object(forKey: url as NSURL), cached.decodedPixelSize >= loaded.decodedPixelSize { return }
                    cache.setObject(loaded, forKey: url as NSURL, cost: loaded.cost)
                }
            }
            preloadQueue.addOperation(operation)
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
        selectAllButton.isEnabled = !files.isEmpty && !exporting && !scanningFolder
    }
    private func updateViewControls() {
        fitCheckbox.state = canvas.fitToScreen ? .on : .off
        zoomLabel.stringValue = "\(Int((canvas.displayScale * 100).rounded())) %"
        guard !galleryVisible, !exporting, !refiningImage, !loadingImage, canvas.image != nil,
              let currentMetadata, !currentMetadata.satisfies(pixelLimit: desiredPreviewPixels) else { return }
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, !self.refiningImage, self.canvas.image != nil else { return }
            self.displayCurrent(resetViewport: false, keepVisible: true)
        }
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
            alert.window.orderOut(nil)
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
        if menuItem.action == #selector(exportSelected) { return galleryVisible && !gallery.selectedIndices.isEmpty && !exporting && !scanningFolder }
        if menuItem.action == #selector(trashCurrent) { return !galleryVisible && !exporting && !scanningFolder && !files.isEmpty }
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

extension ViewerWindowController {
    private var unsavedURLs: [URL] {
        edits.keys.filter { !(edits[$0] ?? []).isEmpty && edits[$0] != savedEdits[$0] }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func prepareToLeave(_ completion: @escaping (Bool) -> Void) {
        stopSlideshow()
        guard !exporting, !leavePromptVisible, let window, window.attachedSheet == nil else { completion(false); return }
        let dirty = unsavedURLs
        guard !dirty.isEmpty else { completion(true); return }
        leavePromptVisible = true
        let alert = NSAlert()
        alert.messageText = "Neuložené úpravy"
        alert.informativeText = "Změny obsahuje \(dirty.count) obrázků. Chcete je uložit před pokračováním?\n\n" + dirty.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: "Uložit vše…")
        alert.addButton(withTitle: "Zahodit změny")
        alert.addButton(withTitle: "Zrušit")
        alert.beginSheetModal(for: window) { [self] response in
            alert.window.orderOut(nil)
            leavePromptVisible = false
            if response == .alertFirstButtonReturn {
                chooseBatchExport(dirty) { completion($0) }
            } else if response == .alertSecondButtonReturn {
                edits.removeAll(); savedEdits.removeAll(); completion(true)
            } else { completion(false) }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closingApproved { return true }
        prepareToLeave { [weak self] allowed in
            guard let self, allowed else { return }
            self.closingApproved = true
            DispatchQueue.main.async { sender.performClose(nil) }
        }
        return false
    }

    private func report(_ title: String, _ details: String) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title; alert.informativeText = details
        alert.beginSheetModal(for: window)
    }

    private var actionURLs: [URL] {
        if galleryVisible { return gallery.selectedIndices.filter { files.indices.contains($0) }.map { files[$0] } }
        return files.indices.contains(index) ? [files[index]] : []
    }

    @objc func revealInFinder() {
        let urls = actionURLs
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
    @objc func copyFilePath() {
        let urls = actionURLs
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    @objc private func changeGallerySize() {
        preferences.galleryThumbnailSize = gallerySize.doubleValue
        gallery.setThumbnailSize(gallerySize.doubleValue)
    }
    @objc private func changeSelectionMode() {
        gallery.setSelectionMode(selectionToggle.state == .on)
        updateGallerySelection()
    }
    private func updateGallerySelection() {
        guard galleryVisible else { return }
        let count = gallery.selectedIndices.count
        batchButton.isEnabled = count > 0 && !exporting && !scanningFolder
        status.stringValue = "Galerie · \(files.count) obrázků · vybráno \(count)" + (scanningFolder ? " · načítám složku…" : "")
    }
    @objc func exportSelected() {
        guard !scanningFolder else { return }
        stopSlideshow()
        let urls = actionURLs
        if !urls.isEmpty { chooseBatchExport(urls) { _ in } }
    }

    @objc func selectAllGallery() { _ = selectAllGalleryIfVisible() }
    @discardableResult func selectAllGalleryIfVisible() -> Bool {
        guard galleryVisible, !exporting, !scanningFolder, window?.attachedSheet == nil else { return false }
        selectionToggle.state = .on
        gallery.setSelectionMode(true)
        gallery.selectAllImages()
        gallery.focus()
        return true
    }

    private func chooseBatchExport(_ sources: [URL], completion: @escaping (Bool) -> Void) {
        guard !sources.isEmpty, !exporting, let window, window.attachedSheet == nil else { completion(false); return }
        let dialog = NSAlert()
        dialog.alertStyle = .informational
        dialog.messageText = "Operace s vybranými obrázky"
        dialog.informativeText = "Vybráno \(sources.count) obrázků. Rotace se provede před změnou rozměrů. Výsledky se uloží jako kopie."
        let confirm = dialog.addButton(withTitle: "Provést")
        dialog.addButton(withTitle: "Zrušit")
        let options = ExportOptionsView(batch: true)
        options.validationChanged = { [weak confirm] valid in confirm?.isEnabled = valid }
        dialog.accessoryView = options
        dialog.beginSheetModal(for: window) { [weak self] response in
            dialog.window.orderOut(nil)
            guard let self, response == .alertFirstButtonReturn, options.validResize else { completion(false); return }
            // Continue only once AppKit has detached the options sheet.
            DispatchQueue.main.async {
                let currentDirectory = sources[0].deletingLastPathComponent()
                switch options.destination {
                case .currentFolder:
                    self.runBatch(sources: sources, directory: currentDirectory, options: options, completion: completion)
                case .newSubfolder:
                    let folder = currentDirectory.appendingPathComponent("Image Viewer export-" + UUID().uuidString.prefix(8))
                    self.runBatch(sources: sources, directory: folder, options: options, createDirectory: true, completion: completion)
                case .chosenFolder:
                    let panel = NSOpenPanel()
                    panel.title = "Cílová složka pro upravené kopie"
                    panel.prompt = "Uložit sem"
                    panel.canChooseDirectories = true; panel.canChooseFiles = false
                    panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
                    panel.directoryURL = currentDirectory
                    panel.beginSheetModal(for: window) { response in
                        let destination = panel.url
                        panel.orderOut(nil)
                        guard response == .OK, let destination else { completion(false); return }
                        DispatchQueue.main.async {
                            self.runBatch(sources: sources, directory: destination, options: options, completion: completion)
                        }
                    }
                }
            }
        }
    }

    private func runBatch(sources: [URL], directory: URL, options: ExportOptionsView, createDirectory: Bool = false, completion: @escaping (Bool) -> Void) {
        guard let window else { completion(false); return }
        exporting = true
        let format = options.format, settings = options.settings, resize = options.resizeTo, keepAspect = options.keepAspect
        let histories = edits
        let operations = options.operations, keepOriginalFormat = options.keepOriginalFormat, onlyReduce = options.onlyReduce
        let folder = directory
        let selectedURLs = Set(gallery.selectedIndices.filter { files.indices.contains($0) }.map { files[$0] })
        let progress = Progress(totalUnitCount: Int64(sources.count))
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Dávkový export"
        let label = NSTextField(labelWithString: "Připravuji export…")
        label.frame = NSRect(x: 20, y: 80, width: 390, height: 20)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 54, width: 390, height: 16))
        bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = Double(sources.count)
        let cancel = ActionButton(title: "Zastavit po aktuální fotce") { progress.cancel() }
        cancel.frame = NSRect(x: 170, y: 12, width: 240, height: 30)
        for view in [label, bar, cancel] { sheet.contentView?.addSubview(view) }
        window.beginSheet(sheet)
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            bar.doubleValue = Double(progress.completedUnitCount)
            label.stringValue = "Hotovo \(progress.completedUnitCount) / \(sources.count)"
        }
        RunLoop.main.add(timer, forMode: .common)
        cancelPreviewWork()
        let previewQueue = queue
        let fastQueue = quickQueue, neighborQueue = preloadQueue
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            previewQueue.waitUntilAllOperationsAreFinished()
                fastQueue.waitUntilAllOperationsAreFinished()
                neighborQueue.waitUntilAllOperationsAreFinished()
            let result = Result { try BatchExporter.write(sources: sources, histories: histories, directory: folder, format: format, settings: settings, resize: resize, keepAspect: keepAspect, progress: progress, operations: operations, createDirectory: createDirectory, keepOriginalFormat: keepOriginalFormat, onlyReduce: onlyReduce) }
            DispatchQueue.main.async { [self] in
                timer.invalidate(); window.endSheet(sheet); sheet.orderOut(nil); exporting = false
                updateViewControls()
                var complete = false
                let alert = NSAlert()
                switch result {
                case .success(let batch):
                    for source in batch.saved.keys where edits[source] == histories[source] { savedEdits[source] = histories[source] ?? [] }
                    complete = batch.saved.count == sources.count && !batch.cancelled && batch.failures.isEmpty
                    alert.messageText = batch.cancelled ? "Export zastaven" : "Export dokončen"
                    alert.informativeText = "Uloženo \(batch.saved.count) / \(sources.count) obrázků.\n\(folder.path)" + (batch.failures.isEmpty ? "" : "\n\nChyby:\n" + batch.failures.joined(separator: "\n"))
                case .failure(let error):
                    alert.messageText = "Export selhal"; alert.informativeText = error.localizedDescription
                }
                alert.addButton(withTitle: "Hotovo")
                alert.addButton(withTitle: "Zobrazit ve Finderu")
                gallery.invalidateThumbnails()
                if files.indices.contains(index) {
                    let current = files[index]
                    if let refreshed = try? ImageFolder.images(beside: current) {
                        files = refreshed
                        index = files.firstIndex(of: current) ?? 0
                        if galleryVisible {
                            gallery.show(files: files, currentIndex: index)
                            gallery.selectImages(at: files.indices.filter { selectedURLs.contains(files[$0]) })
                        }
                    }
                }
                updateButtons()
                updateGallerySelection()
                alert.beginSheetModal(for: window) { response in
                    alert.window.orderOut(nil)
                    if response == .alertSecondButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    completion(complete)
                }
            }
        }
    }

    @objc func startSlideshow() {
        guard files.count > 1, !exporting, let window, window.attachedSheet == nil else { return }
        stopSlideshow()
        let alert = NSAlert()
        alert.messageText = "Prezentace obrázků"
        alert.informativeText = "Interval v sekundách (1–60). Prezentace poběží přes celou obrazovku. Esc ji ukončí."
        let field = NSTextField(string: String(Int(preferences.slideshowInterval)))
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Spustit"); alert.addButton(withTitle: "Zrušit")
        alert.beginSheetModal(for: window) { [weak self] response in
            alert.window.orderOut(nil)
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let interval = Double(field.stringValue), interval.isFinite, (1...60).contains(interval) else {
                self.report("Neplatný interval", "Zadejte číslo od 1 do 60 sekund."); return
            }
            self.preferences.slideshowInterval = interval
            self.setGalleryVisible(false)
            self.canvas.cancelCrop()
            self.slideshowEnteredFullscreen = !window.styleMask.contains(.fullScreen)
            if self.slideshowEnteredFullscreen { window.toggleFullScreen(nil) }
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                guard let self, !self.loadingImage, !self.canvas.isComparing, window.attachedSheet == nil else { return }
                self.navigate(1)
            }
            self.slideTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    @objc func stopSlideshow() {
        slideTimer?.invalidate(); slideTimer = nil
        if slideshowEnteredFullscreen, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        slideshowEnteredFullscreen = false
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        slideshowEnteredFullscreen = false; slideTimer?.invalidate(); slideTimer = nil
    }

    @objc func trashCurrent() {
        guard !galleryVisible, !exporting, !scanningFolder, files.indices.contains(index), let window, window.attachedSheet == nil else { return }
        stopSlideshow()
        let source = files[index]
        let alert = NSAlert()
        alert.messageText = "Přesunout obrázek do koše?"
        alert.informativeText = source.lastPathComponent + "\nSoubor lze vrátit příkazem Vrátit poslední obrázek z koše."
        alert.addButton(withTitle: "Do koše"); alert.addButton(withTitle: "Zrušit")
        let token = generation
        alert.beginSheetModal(for: window) { [weak self] response in
            alert.window.orderOut(nil)
            guard let self, response == .alertFirstButtonReturn, self.generation == token else { return }
            do {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: source, resultingItemURL: &trashed)
                if let trashed {
                    self.trashHistory.append((source, trashed as URL, self.edits[source] ?? [], self.savedEdits[source]))
                }
                self.edits[source] = nil; self.savedEdits[source] = nil
                self.cache.removeObject(forKey: source as NSURL)
                self.files.remove(at: self.index)
                self.index = min(self.index, max(0, self.files.count - 1))
                self.gallery.invalidateThumbnails()
                if self.files.isEmpty { self.showEmptyFolder() } else { self.displayCurrent() }
            } catch { self.report("Přesun do koše selhal", error.localizedDescription) }
        }
    }
    @objc func restoreFromTrash() {
        guard !exporting, let last = trashHistory.last, window?.attachedSheet == nil else { return }
        stopSlideshow()
        let sameFolder = files.isEmpty || files.first.map { ImageFolder.canonicalURL($0.deletingLastPathComponent()) } == ImageFolder.canonicalURL(last.original.deletingLastPathComponent())
        if sameFolder { restoreLastTrash(switchFolder: false) }
        else {
            prepareToLeave { [weak self] allowed in
                if allowed { self?.restoreLastTrash(switchFolder: true) }
            }
        }
    }
    private func restoreLastTrash(switchFolder: Bool) {
        guard let last = trashHistory.last else { return }
        do {
            try FileManager.default.moveItem(at: last.trashed, to: last.original)
            trashHistory.removeLast()
            gallery.invalidateThumbnails()
            if switchFolder {
                openConfirmed(last.original)
                edits[last.original] = last.edits
                savedEdits[last.original] = last.saved
            } else {
                let current = files.indices.contains(index) ? files[index] : last.original
                files = try ImageFolder.images(beside: last.original)
                edits[last.original] = last.edits
                savedEdits[last.original] = last.saved
                index = files.firstIndex(of: current) ?? files.firstIndex(of: last.original) ?? 0
                if galleryVisible { gallery.show(files: files, currentIndex: index); updateGallerySelection() }
                else { displayCurrent() }
            }
        } catch { report("Obnovení z koše selhalo", error.localizedDescription) }
    }
    private func showEmptyFolder() {
        generation = UUID(); folderGeneration = UUID(); folderQueue.cancelAllOperations(); scanningFolder = false
        cancelPreviewWork(); loadingImage = false
        canvas.image = nil; canvas.originalImage = nil; canvas.endComparison()
        currentMetadata = nil; currentSize = nil; copyExifButton.isEnabled = false
        imageDetails.stringValue = ""; canvas.message = "Ve složce nejsou obrázky"
        status.stringValue = "Ve složce nejsou obrázky"; infoText.string = ""
        window?.title = "Image Viewer"
        updateButtons()
    }
}

private final class ActionButton: NSButton {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title; bezelStyle = .rounded
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}
