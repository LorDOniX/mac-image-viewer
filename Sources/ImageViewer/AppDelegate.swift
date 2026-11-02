import AppKit
import ViewerCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var viewer: ViewerWindowController!
    private var terminationPending = false
    private let defaultApplications = DefaultApplicationsController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureWindow()
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        // Also support launching the executable directly with a file argument.
        if let path = CommandLine.arguments.dropFirst().first, !path.hasPrefix("-") {
            viewer.open(URL(fileURLWithPath: path))
        }
    }

    private func ensureWindow() {
        if viewer == nil { viewer = ViewerWindowController() }
        viewer.showWindow(nil)
        viewer.window?.makeKeyAndOrderFront(nil)
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        ensureWindow()
        if let url = urls.first { viewer.open(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ensureWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewer != nil else { return .terminateNow }
        if terminationPending { return .terminateLater }
        terminationPending = true
        DispatchQueue.main.async { [self] in
            viewer.prepareToLeave { [self] allowed in
                terminationPending = false
                sender.reply(toApplicationShouldTerminate: allowed)
            }
        }
        return .terminateLater
    }

    @objc private func openFile() { ensureWindow(); viewer.chooseFile() }
    @objc private func selectAllItems(_ sender: Any?) {
        if viewer?.selectAllGalleryIfVisible() == true { return }
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: sender)
    }
    @objc private func toggleInfo() { viewer.toggleInfo() }
    @objc private func toggleFullscreen() { viewer.window?.toggleFullScreen(nil) }
    @objc private func setDefaultApplications() {
        ensureWindow()
        if let window = viewer.window { defaultApplications.present(for: window) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(setDefaultApplications) || !defaultApplications.isBusy
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let defaults = appMenu.addItem(withTitle: "Nastavit jako výchozí prohlížeč obrázků…", action: #selector(setDefaultApplications), keyEquivalent: "")
        defaults.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ukončit Image Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Soubor")
        let open = fileMenu.addItem(withTitle: "Otevřít obrázek…", action: #selector(openFile), keyEquivalent: "o")
        open.target = self
        let save = fileMenu.addItem(withTitle: "Uložit jako…", action: #selector(ViewerWindowController.saveAs), keyEquivalent: "s")
        save.target = viewer
        fileMenu.addItem(withTitle: "Zavřít okno", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Úpravy")
        func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], in submenu: NSMenu) {
            let entry = submenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            entry.target = viewer
            entry.keyEquivalentModifierMask = modifiers
        }
        item("Operace s vybranými…", #selector(ViewerWindowController.exportSelected), in: fileMenu)
        item("Zobrazit ve Finderu", #selector(ViewerWindowController.revealInFinder), key: "r", modifiers: [.command, .shift], in: fileMenu)
        item("Kopírovat cestu k souboru", #selector(ViewerWindowController.copyFilePath), key: "c", modifiers: [.command, .option], in: fileMenu)
        fileMenu.addItem(.separator())
        item("Přesunout do koše…", #selector(ViewerWindowController.trashCurrent), key: "\u{8}", in: fileMenu)
        item("Vrátit poslední obrázek z koše", #selector(ViewerWindowController.restoreFromTrash), key: "z", modifiers: [.command, .shift], in: fileMenu)
        item("Zpět – poslední úprava", #selector(ViewerWindowController.undoEdit), key: "z", in: editMenu)
        editMenu.addItem(.separator())
        item("Otočit doleva o 90°", #selector(ViewerWindowController.rotateLeft), key: "l", in: editMenu)
        item("Otočit doprava o 90°", #selector(ViewerWindowController.rotateRight), key: "r", in: editMenu)
        item("Převrátit vodorovně", #selector(ViewerWindowController.flipHorizontal), in: editMenu)
        item("Převrátit svisle", #selector(ViewerWindowController.flipVertical), in: editMenu)
        editMenu.addItem(.separator())
        item("Výřez…", #selector(ViewerWindowController.beginCrop), key: "k", in: editMenu)
        item("Změnit rozměry…", #selector(ViewerWindowController.resizeImage), in: editMenu)
        item("Potvrdit výřez", #selector(ViewerWindowController.confirmCrop), in: editMenu)
        item("Zrušit výřez", #selector(ViewerWindowController.cancelCrop), in: editMenu)
        item("Obnovit původní obrázek", #selector(ViewerWindowController.resetEdits), in: editMenu)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Kopírovat", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        item("Kopírovat EXIF jako JSON", #selector(ViewerWindowController.copyExifJSON), key: "c", modifiers: [.command, .shift], in: editMenu)
        let selectAll = editMenu.addItem(withTitle: "Vybrat vše", action: #selector(selectAllItems(_:)), keyEquivalent: "a")
        selectAll.target = self
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Zobrazení")
        item("Spustit prezentaci…", #selector(ViewerWindowController.startSlideshow), key: "p", in: viewMenu)
        item("Zastavit prezentaci", #selector(ViewerWindowController.stopSlideshow), key: ".", in: viewMenu)
        viewMenu.addItem(.separator())
        let comparisonHint = NSMenuItem(title: "Porovnání s originálem: podržte B", action: nil, keyEquivalent: "")
        viewMenu.addItem(comparisonHint)
        item("Galerie", #selector(ViewerWindowController.toggleGallery), key: "g", in: viewMenu)
        viewMenu.addItem(.separator())
        item("Přiblížit", #selector(ViewerWindowController.zoomIn), key: "+", in: viewMenu)
        item("Oddálit", #selector(ViewerWindowController.zoomOut), key: "-", in: viewMenu)
        item("Skutečná velikost (100 %)", #selector(ViewerWindowController.actualSize), key: "0", in: viewMenu)
        item("Přizpůsobit oknu", #selector(ViewerWindowController.toggleFit), key: "9", in: viewMenu)
        viewMenu.addItem(.separator())
        let info = viewMenu.addItem(withTitle: "Informace o obrázku", action: #selector(toggleInfo), keyEquivalent: "i")
        info.target = self
        let fullscreen = viewMenu.addItem(withTitle: "Celá obrazovka", action: #selector(toggleFullscreen), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.control, .command]
        fullscreen.target = self
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        NSApp.mainMenu = menu
    }
}
