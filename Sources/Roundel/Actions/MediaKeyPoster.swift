import AppKit
import RoundelCore

/// Posts the same system-defined events a keyboard's media keys produce, so they reach whichever app owns Now Playing.
/// macOS only delivers synthetic key events from trusted processes: the Accessibility permission is checked by the
/// executor before this runs.
@MainActor
struct MediaKeyPoster: MediaKeySending {
    private static let playCode = 16   // NX_KEYTYPE_PLAY
    private static let nextCode = 17   // NX_KEYTYPE_NEXT
    private static let previousCode = 18   // NX_KEYTYPE_PREVIOUS

    func send(_ key: MediaKey) {
        let code: Int
        switch key {
        case .playPause: code = Self.playCode
        case .next: code = Self.nextCode
        case .previous: code = Self.previousCode
        }
        post(code, down: true)
        post(code, down: false)
    }

    private func post(_ code: Int, down: Bool) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: (code << 16) | (state << 8),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}
