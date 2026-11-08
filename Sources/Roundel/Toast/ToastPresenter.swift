import AppKit
import SwiftUI
import RoundelCore

/// Shows toasts like system banners: top right under the menu bar, newest on top, up to three with "+N more" for the
/// rest, a progress toast updated in place. Auto-dismiss pauses while the pointer is over the stack. Never takes focus.
///
/// What is on screen and when it leaves is decided by `ToastQueue` (pure, tested); this class only shows it.
@MainActor
final class ToastPresenter {
    private let metrics = DesignMetrics.standard
    private var queue = ToastQueue()
    private let model = ToastStackModel()
    private var panel: ToastPanel?
    private var anchorArea: NSRect?
    private var expiryTask: Task<Void, Never>?
    private var shrinkTask: Task<Void, Never>?
    private let clock: () -> TimeInterval
    private let areaProvider: @MainActor () -> NSRect

    private var now: TimeInterval { clock() }

    /// - Parameters:
    ///   - clock: seconds; replaceable so time can be moved in tests.
    ///   - areaProvider: the usable area (below the menu bar) of the screen to show on; by default the one under the pointer.
    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         areaProvider: @escaping @MainActor () -> NSRect = ToastPresenter.areaUnderPointer) {
        self.clock = clock
        self.areaProvider = areaProvider
    }

    // What is shown, for tests.
    var stackEntries: [ToastQueue.Entry] { model.entries }
    var stackHiddenCount: Int { model.hiddenCount }
    var panelForTesting: NSPanel? { panel }

    /// A running action's status ("Converting 4/10"): updated in place, not logged line by line.
    func showProgress(_ message: String) {
        show(message, kind: .progress, logged: false)
    }

    func show(_ message: String, isError: Bool = false, logged: Bool = true) {
        show(message, kind: ToastKind(isError: isError), logged: logged)
    }

    func show(_ text: String, kind: ToastKind, logged: Bool = true) {
        // Toasts vanish after a few seconds; keep a trace for diagnosing and for scripted checks.
        if logged {
            let label = kind == .success ? "" : " (\(kind == .warning ? "warning" : "error"))"
            Log.info("toast\(label): \(text.replacingOccurrences(of: "\n", with: " / "))")
        }
        queue.push(ToastMessage.parse(text, kind: kind), now: now)
        if kind != .progress { announce(text) }
        refresh()
    }

    // MARK: Showing what the queue says

    func refresh() {
        queue.advance(to: now)
        let entries = queue.visible
        let changed = entries.map(\.id) != model.entries.map(\.id)
        let motion = metrics.resolve(metrics.appearMotion, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        withAnimation(changed ? motion.animation : nil) {
            model.entries = entries
            model.hiddenCount = queue.hiddenCount
        }
        layoutPanel(entries: entries)
        scheduleExpiry()
    }

    private func layoutPanel(entries: [ToastQueue.Entry]) {
        shrinkTask?.cancel()
        guard !entries.isEmpty else {
            // Let the exit animation play, then take the window away.
            shrinkTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self, self.queue.entries.isEmpty else { return }
                self.panel?.orderOut(nil)
                self.anchorArea = nil
            }
            return
        }

        let size = ToastLayout.stackSize(cardHeights: entries.map { ToastLayout.cardSize(for: $0.message).height }, hasMore: queue.hiddenCount > 0)
        let area = anchorArea ?? areaProvider()
        anchorArea = area
        let target = ToastLayout.panelFrame(size: size, in: area)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.isVisible, target.height < panel.frame.height {
            // Smaller: keep the room until the toast that left has finished leaving.
            shrinkTask = Task { [weak panel] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                panel?.setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let seconds = queue.secondsUntilNextExpiry else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(seconds, 0.01) + 0.02))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// The pointer entered or left the stack: while it is over it, nothing expires.
    func hover(_ inside: Bool) {
        queue.setPaused(inside, now: now)
        scheduleExpiry()
    }

    // MARK: Window

    private func makePanel() -> ToastPanel {
        let panel = ToastPanel(rootView: ToastStackView(model: model))
        panel.hostingView.onHover = { [weak self] inside in
            MainActor.assumeIsolated { self?.hover(inside) }
        }
        return panel
    }

    /// The usable area (below the menu bar) of the screen the pointer is on.
    static func areaUnderPointer() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// VoiceOver reads the toast aloud; sighted users see it, blind users would otherwise never know.
    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
