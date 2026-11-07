import AppKit
import RoundelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var toast: ToastPresenter?
    private var store: ConfigStore?
    private var coordinator: RingCoordinator?
    private var warnings: ConfigWarningsReporter?
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityStatus.logCurrent()
        // Probe BEFORE the library registers the shortcut (see HotkeyProbe).
        HotkeyProbe.logOpenRingStatus()

        let toast = ToastPresenter()
        let store = ConfigStore(toast: toast)

        let registry = ActionRegistry.standard(services: .system())
        for id in registry.duplicateIDs { Log.warning("Action id '\(id)' is registered twice; the first one wins") }
        let executor = ActionExecutor(registry: registry, permissions: SystemPermissions(), reporter: AppActionReporter(toast: toast))
        let coordinator = RingCoordinator(iconStore: IconStore(baseDirectory: store.directory), registry: registry, executor: executor)
        let warnings = ConfigWarningsReporter(registry: registry, toast: toast)

        // The ring is built only from config: wire it up first, then load (which also applies the initial config).
        store.onChange = { [weak coordinator, weak warnings] config in
            coordinator?.applyConfig(config)
            warnings?.check(config)
        }
        coordinator.start()
        store.start()

        statusMenu = StatusMenuController(store: store)
        self.toast = toast
        self.store = store
        self.coordinator = coordinator
        self.warnings = warnings
    }
}
