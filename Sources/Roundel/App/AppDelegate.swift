import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = RingSettings()
    private var coordinator: RingCoordinator?
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityStatus.logCurrent()
        // Probe BEFORE the library registers the shortcut (see HotkeyProbe).
        HotkeyProbe.logOpenRingStatus()

        let coordinator = RingCoordinator(settings: settings)
        coordinator.start()
        self.coordinator = coordinator

        statusMenu = StatusMenuController(settings: settings)
    }
}
