import AppKit
import ViewerCore

private final class ThumbnailBox: NSObject {
    let bitmap: CGImage
    init(_ bitmap: CGImage) { self.bitmap = bitmap }
}

private final class ThumbnailLoader {
    private let queue = OperationQueue()
    private let cache = NSCache<NSURL, ThumbnailBox>()

    init() {
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func load(_ url: URL, completion: @escaping (CGImage?) -> Void) -> Operation? {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached.bitmap)
            return nil
        }
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation, cache] in
            guard operation?.isCancelled == false else { return }
            let image = autoreleasepool { ImageThumbnail.load(url: url) }
            guard operation?.isCancelled == false else { return }
            if let image { cache.setObject(ThumbnailBox(image), forKey: url as NSURL, cost: image.bytesPerRow * image.height) }
            DispatchQueue.main.async {
                guard operation?.isCancelled == false else { return }
                completion(image)
            }
        }
        queue.addOperation(operation)
        return operation
    }

    func cancel() { queue.cancelAllOperations() }
    func invalidate() { cancel(); cache.removeAllObjects() }
}

private final class GalleryItem: NSCollectionViewItem {
    private var request: Operation?
    private var representedURL: URL?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        let preview = NSImageView()
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.imageAlignment = .alignCenter
        let name = NSTextField(labelWithString: "")
        name.font = .systemFont(ofSize: 12)
        name.textColor = .white
        name.alignment = .center
        name.lineBreakMode = .byTruncatingMiddle
        for child in [preview, name] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            preview.bottomAnchor.constraint(equalTo: name.topAnchor, constant: -8),
            name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            name.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            name.heightAnchor.constraint(equalToConstant: 18)
        ])
        imageView = preview
        textField = name
        updateSelection()
    }

    override var isSelected: Bool { didSet { if isViewLoaded { updateSelection() } } }
    private func updateSelection() {
        view.layer?.backgroundColor = NSColor(calibratedWhite: isSelected ? 0.2 : 0.12, alpha: 1).cgColor
        view.layer?.borderWidth = isSelected ? 2 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    func configure(url: URL, loader: ThumbnailLoader) {
        _ = view
        request?.cancel()
        representedURL = url
        textField?.stringValue = url.lastPathComponent
        view.toolTip = url.lastPathComponent
        imageView?.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Načítání náhledu")
        imageView?.setAccessibilityLabel(url.lastPathComponent)
        request = loader.load(url) { [weak self] bitmap in
            guard let self, self.representedURL == url else { return }
            if let bitmap {
                self.imageView?.image = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
            } else {
                self.imageView?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Náhled nelze načíst")
                self.view.toolTip = "\(url.lastPathComponent) – náhled nelze načíst"
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        request?.cancel()
        request = nil
        representedURL = nil
        imageView?.image = nil
    }
}

private final class GalleryGrid: NSCollectionView {
    var activate: ((IndexPath) -> Void)?
    var dismiss: (() -> Void)?
    var selectionMode = false
    var contextAction: ((String) -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
        }
        let menu = NSMenu()
        for (title, tag) in [("Zobrazit ve Finderu", 1), ("Kopírovat cestu", 2), ("Exportovat vybrané…", 3)] {
            let item = menu.addItem(withTitle: title, action: #selector(contextMenuAction(_:)), keyEquivalent: "")
            item.tag = tag; item.target = self
        }
        return menu
    }
    @objc private func contextMenuAction(_ sender: NSMenuItem) {
        contextAction?(sender.tag == 1 ? "finder" : sender.tag == 2 ? "path" : "export")
    }

    override func mouseDown(with event: NSEvent) {
        let clicked = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        if let clicked, !selectionMode, event.modifierFlags.intersection([.command, .shift]).isEmpty { activate?(clicked) }
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 123 || event.keyCode == 124),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            let current = selectionIndexPaths.first?.item ?? 0
            let count = numberOfSections > 0 ? numberOfItems(inSection: 0) : 0
            if let next = ImageFolder.nextIndex(current: current, step: event.keyCode == 123 ? -1 : 1, count: count) {
                selectItems(at: [IndexPath(item: next, section: 0)], scrollPosition: .centeredVertically)
            }
        }
        else if event.keyCode == 53 { dismiss?() }
        else if event.keyCode == 36, let selected = selectionIndexPaths.first { activate?(selected) }
        else { super.keyDown(with: event) }
    }
}

final class GalleryView: NSScrollView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let grid = GalleryGrid()
    private let loader = ThumbnailLoader()
    private var files: [URL] = []
    private var updating = false
    var selectImage: ((Int) -> Void)?
    var closeGallery: (() -> Void)?
    var selectionChanged: (() -> Void)?
    var contextAction: ((String) -> Void)?
    var selectedIndices: [Int] { grid.selectionIndexPaths.map(\.item).sorted() }
    func setSelectionMode(_ enabled: Bool) { grid.selectionMode = enabled }
    func setThumbnailSize(_ width: Double) {
        guard let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let width = max(130, min(340, width))
        layout.itemSize = NSSize(width: width, height: width * 0.72 + 40)
        layout.invalidateLayout()
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { selectionChanged?() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { selectionChanged?() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        drawsBackground = true
        backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 200, height: 184)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        grid.collectionViewLayout = layout
        grid.backgroundColors = [backgroundColor]
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.delegate = self
        grid.contextAction = { [weak self] in self?.contextAction?($0) }
        grid.dataSource = self
        grid.activate = { [weak self] path in
            guard let self, !self.updating, self.files.indices.contains(path.item) else { return }
            self.selectImage?(path.item)
        }
        grid.dismiss = { [weak self] in self?.closeGallery?() }
        grid.register(GalleryItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("Photo"))
        grid.autoresizingMask = [.width]
        grid.frame = contentView.bounds
        documentView = grid
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(files: [URL], currentIndex: Int) {
        updating = true
        self.files = files
        grid.reloadData()
        layoutSubtreeIfNeeded()
        if files.indices.contains(currentIndex) {
            let selected: Set<IndexPath> = [IndexPath(item: currentIndex, section: 0)]
            grid.selectionIndexPaths = selected
            grid.scrollToItems(at: selected, scrollPosition: .centeredVertically)
        }
        updating = false
    }

    func suspend() { loader.cancel() }
    func invalidateThumbnails() { loader.invalidate() }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { files.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("Photo"), for: indexPath) as! GalleryItem
        item.configure(url: files[indexPath.item], loader: loader)
        return item
    }

    func focus() { window?.makeFirstResponder(grid) }
}
