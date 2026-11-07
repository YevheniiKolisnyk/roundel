import RoundelCore

/// Checks a loaded config against the action registry. Every warning goes to the log each time; the toast appears
/// only when the set of warnings changes, so hot-reloading an unchanged config does not nag.
@MainActor
final class ConfigWarningsReporter {
    private let registry: ActionRegistry
    private let toast: ToastPresenter
    private var tracker = WarningTracker()

    init(registry: ActionRegistry, toast: ToastPresenter) {
        self.registry = registry
        self.toast = toast
    }

    func check(_ config: RoundelConfig) {
        let warnings = registry.warnings(for: config)
        for warning in warnings {
            Log.warning("config: \(warning)")
        }
        if tracker.update(warnings) {
            let count = warnings.count
            toast.show("Config loaded with \(count) warning\(count == 1 ? "" : "s"). Details: Console.app, search “app.roundel”.", isError: true)
        }
    }
}
