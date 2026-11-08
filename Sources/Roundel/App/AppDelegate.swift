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
        logSurface()

        let toast = ToastPresenter()
        let store = ConfigStore(toast: toast)

        let services = ActionServices.system()
        let registry = ActionRegistry.standard(services: services)
        let generators = NodeGeneratorRegistry.standard(services: services)
        for id in registry.duplicateIDs { Log.warning("Action id '\(id)' is registered twice; the first one wins") }
        let executor = ActionExecutor(registry: registry, permissions: SystemPermissions(), reporter: AppActionReporter(toast: toast))
        let coordinator = RingCoordinator(iconStore: IconStore(baseDirectory: store.directory), registry: registry, executor: executor)
        let warnings = ConfigWarningsReporter(registry: registry, toast: toast)

        // The ring is built only from config: wire it up first, then load (which also applies the initial config).
        // Groups with "generate" are filled in here, so the ring and the checks see the finished config.
        store.onChange = { [weak coordinator, weak warnings] config in
            let resolved = ConfigResolver.resolve(config, generators: generators)
            coordinator?.applyConfig(resolved.config)
            warnings?.check(resolved.config, extra: resolved.warnings)
        }
        coordinator.start()
        store.start()

        statusMenu = StatusMenuController(store: store)
        self.toast = toast
        self.store = store
        self.coordinator = coordinator
        self.warnings = warnings
    }

    /// Says which kind of surface everything is drawn on, so `ROUNDEL_SURFACE` is never a mystery.
    private func logSurface() {
        let preference = SurfacePreference.fromProcessEnvironment
        let style = SurfaceStyle.resolve(preference: preference, glassAvailable: Platform.supportsGlass,
                                         reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        let reason = preference == .automatic ? "" : " (ROUNDEL_SURFACE=\(preference.rawValue))"
        Log.info("Surfaces: \(style)\(reason); glass available: \(Platform.supportsGlass)")
    }
}
