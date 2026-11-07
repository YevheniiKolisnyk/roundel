import AppKit
import SwiftUI

/// Small transient message in the top-right corner. Used instead of system notifications, which crash for an
/// unbundled executable and would need a permission. Never takes focus and ignores the mouse.
@MainActor
final class ToastPresenter {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// A running action's status ("Converting 4/10"): replaces the toast on screen and is not logged line by line.
    func showProgress(_ message: String) {
        show(message, isError: false, logged: false)
    }

    func show(_ message: String, isError: Bool = false, logged: Bool = true) {
        hideTask?.cancel()
        // Toasts vanish after a few seconds; keep a trace for diagnosing and for scripted checks.
        if logged { Log.info("toast\(isError ? " (error)" : ""): \(message.replacingOccurrences(of: "\n", with: " / "))") }

        let hosting = NSHostingView(rootView: ToastView(message: message, isError: isError))
        hosting.sizingOptions = []
        let size = hosting.fittingSize

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 6 : 3))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            MainActor.assumeIsolated {
                if panel?.alphaValue == 0 { panel?.orderOut(nil) }
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 16)
    }
}

private struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.orange : Color.green)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
    }
}
