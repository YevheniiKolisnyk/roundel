import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the ring. Default ⌥⌘Z, rebindable from the status menu.
    static let openRing = KeyboardShortcuts.Name("openRing", initial: .init(.z, modifiers: [.option, .command]))

    /// Esc, enabled only while the ring is open. A global hotkey is used because a non-key panel gets no key events,
    /// and a global key monitor would need the Accessibility permission.
    static let dismissRing = KeyboardShortcuts.Name("dismissRing", initial: .init(.escape))
}
