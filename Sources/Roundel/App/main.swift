import AppKit

// Entry point. Accessory policy = no Dock icon, no menu bar takeover, and lets the panel float over fullscreen apps.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
