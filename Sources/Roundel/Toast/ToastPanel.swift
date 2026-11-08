import AppKit
import SwiftUI

/// The toast stack's view. Reports when the pointer enters or leaves it, so auto-dismiss can pause under the pointer.
/// (The panel is never key, so SwiftUI's own `onHover` is not relied on; an always-active tracking area is.)
final class ToastHostingView: NSHostingView<ToastStackView> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    required init(rootView: ToastStackView) {
        super.init(rootView: rootView)
        sizingOptions = []   // the window decides the size, not SwiftUI
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let new = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(new)
        area = new
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Borderless, transparent, above other windows, never key or main, so it cannot take focus from the frontmost app.
/// Its mouse handling is left at the default on purpose: clear pixels let clicks through to what is underneath, and
/// assigning `ignoresMouseEvents` would make the whole window swallow them (see CLAUDE.md).
final class ToastPanel: NSPanel {
    let hostingView: ToastHostingView

    init(rootView: ToastStackView) {
        hostingView = ToastHostingView(rootView: rootView)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // the cards draw their own shadow
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
