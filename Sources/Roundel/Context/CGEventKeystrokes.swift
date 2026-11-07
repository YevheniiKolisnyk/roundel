import AppKit
import Carbon.HIToolbox
import RoundelCore

/// Posts Cmd+C / Cmd+V to the frontmost app. Needs the Accessibility permission (checked by the executor).
///
/// The events are the sequence a real keyboard produces: Command down, the letter down and up, Command up. The
/// first version posted only the letter with a Command flag, and that left the system believing Command was still
/// held (`CGEventSource.flagsState` kept reporting it), so the closing Command-up is not optional. The events come
/// from a private source with explicit flags, so modifiers still held from the hotkey do not leak into them.
@MainActor
struct CGEventKeystrokes: KeystrokeSending {
    func send(_ keystroke: Keystroke) async {
        let (character, fallback): (Character, Int) = switch keystroke {
        case .copy: ("c", kVK_ANSI_C)
        case .paste: ("v", kVK_ANSI_V)
        }
        let letter = KeyCodeResolver.keyCode(for: character, fallback: CGKeyCode(fallback))
        guard let source = CGEventSource(stateID: .privateState) else { return }

        func post(_ code: Int, keyDown: Bool, flags: CGEventFlags, modifierChange: Bool = false) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: keyDown)
            if modifierChange { event?.type = .flagsChanged }
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }

        post(kVK_Command, keyDown: true, flags: .maskCommand, modifierChange: true)
        post(Int(letter), keyDown: true, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(5))
        post(Int(letter), keyDown: false, flags: .maskCommand)
        post(kVK_Command, keyDown: false, flags: [], modifierChange: true)
    }
}

/// Finds the key that types a letter on the current ASCII-capable layout, because that is the layout macOS uses to
/// match Command shortcuts (it matters on Dvorak and other non-QWERTY layouts).
enum KeyCodeResolver {
    static func keyCode(for character: Character, fallback: CGKeyCode) -> CGKeyCode {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return fallback }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        for code in 0..<128 {
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
            if status == noErr, length == 1, String(utf16CodeUnits: characters, count: 1).lowercased() == String(character) {
                return CGKeyCode(code)
            }
        }
        return fallback
    }
}
