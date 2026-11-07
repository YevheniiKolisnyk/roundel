import AppKit
import KeyboardShortcuts
import SwiftUI

/// Small window hosting the shortcut recorder. A recorder cannot live inside an NSMenu, so the status menu opens this.
/// This is the only place the app activates itself, and only on an explicit user click.
@MainActor
final class HotkeyWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let content = HStack {
                Text("Open ring:")
                KeyboardShortcuts.Recorder(for: .openRing)
            }
            .padding(20)

            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "Roundel Hotkey"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Re-check after the user may have picked a new combo. Disable first so we do not probe our own registration.
        KeyboardShortcuts.disable(.openRing)
        HotkeyProbe.logOpenRingStatus()
        KeyboardShortcuts.enable(.openRing)
    }
}
