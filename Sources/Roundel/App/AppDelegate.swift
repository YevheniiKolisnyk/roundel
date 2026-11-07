import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var toast: ToastPresenter?
    private var store: ConfigStore?
    private var coordinator: RingCoordinator?
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityStatus.logCurrent()
        // Probe BEFORE the library registers the shortcut (see HotkeyProbe).
        HotkeyProbe.logOpenRingStatus()

        let toast = ToastPresenter()
        let store = ConfigStore(toast: toast)
        let coordinator = RingCoordinator(iconStore: IconStore(baseDirectory: store.directory))

        // The ring is built only from config: wire it up first, then load (which also applies the initial config).
        store.onChange = { [weak coordinator] config in coordinator?.applyConfig(config) }
        coordinator.start()
        store.start()

        statusMenu = StatusMenuController(store: store)
        self.toast = toast
        self.store = store
        self.coordinator = coordinator
    }
}
