import AppKit

/// Status-bar menu. Open mode and section settings now live in config.json; this keeps what a config file cannot do:
/// the hotkey recorder, shortcuts to the config, and Quit. The hotkey stays in UserDefaults via KeyboardShortcuts.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let store: ConfigStore
    private let hotkeyWindow = HotkeyWindowController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(store: ConfigStore) {
        self.store = store
        super.init()
        configureButton()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuild(menu)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Roundel") {
            button.image = image
        } else {
            button.title = "◎"
        }
    }

    // Rebuilt every time the menu opens so the config-error line is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        if let failure = store.lastFailure {
            let error = NSMenuItem(title: "⚠︎ Config error: \(failure.summary)", action: #selector(openConfigFile), keyEquivalent: "")
            error.target = self
            error.toolTip = failure.description + "\n\nClick to open config.json. Roundel keeps using the last working config."
            menu.addItem(error)
            menu.addItem(.separator())
        }

        menu.addItem(item("Set Hotkey…", #selector(openHotkeyWindow)))
        menu.addItem(item("Open Config Folder", #selector(openConfigFolder)))
        menu.addItem(item("Reload Config", #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Roundel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openHotkeyWindow() {
        hotkeyWindow.show()
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(store.directory)
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(store.file)
    }

    @objc private func reloadConfig() {
        store.reload(userInitiated: true)
    }
}
