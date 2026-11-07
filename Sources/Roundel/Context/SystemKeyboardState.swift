import AppKit
import Carbon.HIToolbox
import RoundelCore

@MainActor
struct SystemModifierWatcher: ModifierKeyWatching {
    var anyModifierHeld: Bool {
        !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }
}

/// `IsSecureEventInputEnabled` is global: it is also on while any other app (a password field, Terminal's
/// "Secure Keyboard Entry") holds secure input.
@MainActor
struct SystemSecureInput: SecureInputChecking {
    var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }
}

/// Switches the active keyboard layout among the ones enabled in System Settings.
@MainActor
struct SystemInputSources: InputSourceSwitching {
    func select(inputSourceID: String) throws {
        let name = inputSourceID.split(separator: ".").last.map(String.init) ?? inputSourceID
        let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
        // includeAllInstalled: false = only layouts that are enabled.
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource], let source = list.first else {
            throw ActionError.failed("input source “\(name)” is not enabled (System Settings → Keyboard → Input Sources)")
        }
        guard TISSelectInputSource(source) == noErr else {
            throw ActionError.failed("macOS refused to switch to “\(name)”")
        }
    }
}
