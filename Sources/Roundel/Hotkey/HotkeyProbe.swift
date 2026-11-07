import Carbon.HIToolbox
import KeyboardShortcuts

/// KeyboardShortcuts swallows registration failures silently. This probes the same Carbon call so we can log them.
/// Run it while the shortcut is NOT registered by the library, or it will report our own registration as a conflict.
enum HotkeyProbe {
    static func isAvailable(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x52444C50), id: 1) // 'RDLP'
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode),
            UInt32(shortcut.carbonModifiers),
            id,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        UnregisterEventHotKey(ref)
        return true
    }

    /// Logs the state of the open-ring hotkey. Never throws or crashes.
    @MainActor
    static func logOpenRingStatus() {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .openRing) else {
            Log.warning("No open-ring hotkey is set. Pick one from the status menu: Set Hotkey…")
            return
        }
        if isAvailable(shortcut) {
            Log.info("Open-ring hotkey registered: \(shortcut)")
        } else {
            Log.warning("Open-ring hotkey \(shortcut) could not be registered (already taken by the system or another app). Choose another from the status menu: Set Hotkey…")
        }
    }
}
