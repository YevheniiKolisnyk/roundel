import AppKit
import RoundelCore

/// Temporary scaffolding (milestone 1): open mode, section count, hotkey, quit.
/// Replaced by JSON config in milestone 2 and a real settings UI in milestone 7. Quit stays.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private static let sectionChoices = Array(2...12) + [16, 24]

    private let settings: RingSettings
    private let hotkeyWindow = HotkeyWindowController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let modeMenu = NSMenu()
    private let countMenu = NSMenu()

    init(settings: RingSettings) {
        self.settings = settings
        super.init()
        configureButton()
        statusItem.menu = buildMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Roundel") {
            button.image = image
        } else {
            button.title = "◎"
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let modeItem = NSMenuItem(title: "Open Mode", action: nil, keyEquivalent: "")
        for mode in OpenMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeMenu.addItem(item)
        }
        modeMenu.delegate = self
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let countItem = NSMenuItem(title: "Sections", action: nil, keyEquivalent: "")
        for count in Self.sectionChoices {
            let item = NSMenuItem(title: "\(count)", action: #selector(selectCount(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            countMenu.addItem(item)
        }
        countMenu.delegate = self
        countItem.submenu = countMenu
        menu.addItem(countItem)

        menu.addItem(.separator())

        let hotkeyItem = NSMenuItem(title: "Set Hotkey…", action: #selector(openHotkeyWindow), keyEquivalent: "")
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Roundel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // Refresh checkmarks each time a submenu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === modeMenu {
            for item in menu.items {
                item.state = (item.representedObject as? String) == settings.openMode.rawValue ? .on : .off
            }
        } else if menu === countMenu {
            for item in menu.items {
                item.state = item.tag == settings.sectionCount ? .on : .off
            }
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = OpenMode(rawValue: raw) else { return }
        settings.openMode = mode
    }

    @objc private func selectCount(_ sender: NSMenuItem) {
        settings.sectionCount = sender.tag
    }

    @objc private func openHotkeyWindow() {
        hotkeyWindow.show()
    }
}
