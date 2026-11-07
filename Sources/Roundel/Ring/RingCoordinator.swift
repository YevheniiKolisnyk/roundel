import AppKit
import KeyboardShortcuts
import SwiftUI
import RoundelCore

/// Glue: hotkey and pointer events go into `RingInteraction`; its outcomes drive the panel and the view model.
/// Holds no navigation logic of its own beyond translating screen coordinates to ring offsets.
@MainActor
final class RingCoordinator {
    private let iconStore: IconStore
    private let registry: ActionRegistry
    private let executor: ActionExecutor
    private let model = RingModel()
    private let panel: RingPanel
    private var interaction = RingInteraction()

    /// Config for the ring that is open right now. A reload while the ring is open waits until it closes.
    private var activeConfig = DefaultConfig.config
    private var pendingConfig: RoundelConfig?

    private let metrics = RingMetrics.standard
    private var layout = RingLayout.make(root: [], path: [])
    private var ringCenter = CGPoint.zero
    private var limits = ScreenLimits.fallback
    private var pollTimer: Timer?
    private var clickMonitors: [Any] = []

    /// Size caps and bounds of the screen the ring opened on.
    private struct ScreenLimits {
        var rootMaxOuterRadius: Double
        var arcMaxOuterRadius: Double
        var bounds: CGRect

        static let fallback = ScreenLimits(rootMaxOuterRadius: RingMetrics.standard.rootMaxOuterRadius,
                                           arcMaxOuterRadius: RingMetrics.standard.arcRadiusCap,
                                           bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    init(iconStore: IconStore, registry: ActionRegistry, executor: ActionExecutor) {
        self.iconStore = iconStore
        self.registry = registry
        self.executor = executor
        self.panel = RingPanel(
            rootView: RingView(model: model),
            side: RingMetrics.standard.panelSide(forOuterRadius: RingMetrics.standard.rootMinOuterRadius)
        )
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .openRing) { [weak self] in
            MainActor.assumeIsolated { self?.hotkeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .openRing) { [weak self] in
            MainActor.assumeIsolated { self?.hotkeyUp() }
        }
        KeyboardShortcuts.onKeyDown(for: .dismissRing) { [weak self] in
            MainActor.assumeIsolated { self?.escape() }
        }
        // Registering a handler enables the shortcut immediately; Esc must only be live while the ring is open.
        KeyboardShortcuts.disable(.dismissRing)
    }

    // MARK: Config

    func applyConfig(_ config: RoundelConfig) {
        if interaction.isOpen {
            pendingConfig = config
        } else {
            activate(config)
        }
    }

    private func activate(_ config: RoundelConfig) {
        activeConfig = config
        pendingConfig = nil
        iconStore.reload(for: config)

        for warning in metrics.levelWarnings(in: config) {
            let place = warning.path.isEmpty ? "the top ring" : "group '\(warning.path.joined(separator: " > "))'"
            switch warning.kind {
            case .crowded:
                Log.warning("\(place) has \(warning.count) items, more than fit comfortably on screen. Consider regrouping some of them.")
            case .tooDeep:
                Log.warning("\(place) is nested too deeply to fit on screen (\(warning.path.count) arcs out). Consider flattening the groups.")
            }
        }
    }

    // MARK: Hotkey

    private func hotkeyDown() {
        apply(interaction.hotkeyDown(config: activeConfig))
    }

    private func hotkeyUp() {
        // Look at where the pointer is right now, not where it was at the last frame.
        if interaction.isOpen, interaction.mode == .holdRelease { pollPointer() }
        apply(interaction.hotkeyUp())
    }

    private func escape() {
        apply(interaction.escape())
    }

    // MARK: Outcomes

    private func apply(_ outcome: RingOutcome) {
        switch outcome {
        case .none:
            break
        case .opened:
            open()
        case .layoutChanged:
            withAnimation(.easeOut(duration: 0.12)) { rebuildLayout() }
            // The layout under the pointer is new: tell the state machine what is there now.
            pollPointer()
        case .select(let id):
            run(actionWithID: id)
            close()
        case .dismiss:
            close()
        }
    }

    private func open() {
        let started = DispatchTime.now()
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let mouse = NSEvent.mouseLocation
        limits = Self.screenLimits(at: mouse, metrics: metrics)

        // The ring center stays where the pointer was; later resizes keep it fixed (sides are even whole numbers).
        let rootSide = metrics.panelSide(forOuterRadius: metrics.rootBand(itemCount: interaction.nodes(atLevel: 0).count,
                                                                         maxOuterRadius: limits.rootMaxOuterRadius).outerRadius)
        ringCenter = CGPoint(x: (mouse.x - rootSide / 2).rounded() + rootSide / 2, y: (mouse.y - rootSide / 2).rounded() + rootSide / 2)

        rebuildLayout()
        panel.show(centeredOn: ringCenter, side: model.panelSide)
        pollPointer()
        startTracking()
        KeyboardShortcuts.enable(.dismissRing)

        let millis = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Log.info("Ring opened in \(String(format: "%.1f", millis)) ms (\(interaction.mode.rawValue), \(interaction.nodes(atLevel: 0).count) sections)")

        // Focus check: the frontmost app must be the same one after we show the panel.
        let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if after != frontmostBefore {
            Log.warning("Frontmost app changed on open: \(frontmostBefore ?? "nil") -> \(after ?? "nil")")
        }
    }

    private func close() {
        stopTracking()
        KeyboardShortcuts.disable(.dismissRing)
        // Drop the click footprint first, then stop the panel from taking mouse events, then take it off screen.
        model.footprint = []
        model.bands = []
        model.highlighted = []
        panel.hide()
        if let pendingConfig { activate(pendingConfig) }
    }

    /// Recomputes the layout for the open groups and pushes it to the view model and the panel size.
    private func rebuildLayout() {
        layout = RingLayout.make(
            root: interaction.nodes(atLevel: 0),
            path: interaction.path,
            metrics: metrics,
            rootMaxOuterRadius: limits.rootMaxOuterRadius,
            arcMaxOuterRadius: limits.arcMaxOuterRadius,
            placement: ArcPlacement.Context(ringCenter: ringCenter, bounds: limits.bounds)
        )

        model.bands = layout.bands.map { band in
            let items = RingItem.items(
                for: interaction.nodes(atLevel: band.level),
                isAvailable: { [registry] in registry.isAvailable($0) },
                isActive: { [registry] in registry.isActive($0) },
                defaultIcon: { [registry] in registry.defaultIcon(for: $0) }
            ).map { DisplayItem(item: $0, icon: iconStore.resolve($0)) }
            return BandModel(band: band, items: items, connector: connector(for: band))
        }
        model.highlighted = Set(interaction.highlightedItems)
        model.footprint = layout.footprint
        model.panelSide = metrics.panelSide(forOuterRadius: layout.outerRadius)
        if panel.isVisible { panel.resize(side: model.panelSide) }
    }

    /// The short stub drawn between a parent section and its arc.
    private func connector(for band: RingBand) -> BandModel.Connector? {
        guard band.level > 0, layout.bands.indices.contains(band.level - 1), interaction.path.indices.contains(band.level - 1) else { return nil }
        let parent = layout.bands[band.level - 1]
        let parentID = interaction.path[band.level - 1]
        guard let index = interaction.nodes(atLevel: band.level - 1).firstIndex(where: { $0.id == parentID }) else { return nil }
        return BandModel.Connector(angle: parent.centerAngle(ofItem: index), width: parent.itemWidth,
                                   innerRadius: parent.outerRadius, outerRadius: band.innerRadius, parentID: parentID)
    }

    // MARK: Running actions

    private func run(actionWithID id: String) {
        guard case .action(let action)? = activeConfig.node(withID: id) else {
            Log.warning("Selected '\(id)' but it is not an action node")
            return
        }
        // The ring is already closing; the action runs on its own so a slow one never holds the UI.
        Task { await executor.execute(action) }
    }

    // MARK: Pointer tracking

    private func startTracking() {
        stopTracking()

        // Polling NSEvent.mouseLocation is independent of window event routing: a non-key panel does not reliably
        // receive mouseMoved, and global monitors do not fire for events over our own windows.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: buttons, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerClicked(inThisApp: false) }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: buttons, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerClicked(inThisApp: true) }
            return event
        }) {
            clickMonitors.append(local)
        }
    }

    private func stopTracking() {
        pollTimer?.invalidate()
        pollTimer = nil
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    private func pollPointer() {
        guard interaction.isOpen else { return }
        let now = ProcessInfo.processInfo.systemUptime

        // A layout change can put a different item under the pointer, so ask again (a few times at most).
        for _ in 0..<4 {
            let offset = pointerOffset()
            let outcome = interaction.update(hit: layout.hit(dx: offset.dx, dy: offset.dy), now: now)
            guard outcome == .layoutChanged else { break }
            withAnimation(.easeOut(duration: 0.12)) { rebuildLayout() }
        }

        let highlighted = Set(interaction.highlightedItems)
        if model.highlighted != highlighted { model.highlighted = highlighted }
    }

    private func pointerClicked(inThisApp: Bool) {
        let hit: RingHit
        if inThisApp {
            let offset = pointerOffset()
            hit = layout.hit(dx: offset.dx, dy: offset.dy)
        } else {
            hit = .outside   // a click in another app
        }
        apply(interaction.click(hit))
    }

    /// Cursor offset from the ring center, y-up, in screen points.
    private func pointerOffset() -> (dx: Double, dy: Double) {
        let mouse = NSEvent.mouseLocation
        return (Double(mouse.x - ringCenter.x), Double(mouse.y - ringCenter.y))
    }

    /// Caps that keep the ring inside the screen the pointer is on, and that screen's usable area.
    private static func screenLimits(at point: CGPoint, metrics: RingMetrics) -> ScreenLimits {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .fallback }
        let fits = (Double(min(frame.width, frame.height)) / 2).rounded(.down) - metrics.panelPadding - 8
        return ScreenLimits(
            rootMaxOuterRadius: min(metrics.rootMaxOuterRadius, max(metrics.rootMinOuterRadius, fits)),
            arcMaxOuterRadius: min(metrics.arcRadiusCap, max(metrics.rootMinOuterRadius, fits)),
            bounds: frame
        )
    }
}
