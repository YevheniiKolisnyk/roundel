import AppKit
import SwiftUI

/// How big a toast is and where it goes. Kept apart from the window so it can be measured without showing anything.
///
/// The size comes from SwiftUI for the width the toast may use, so a long message wraps instead of being cut off after
/// its first line. It must never be empty: a window with no area is "on screen" and invisible, which is exactly what
/// every toast was until this was written (reading `fittingSize` of a hosting view with empty `sizingOptions` gives 0 x 0).
enum ToastLayout {
    static let maxWidth: CGFloat = 380
    static let margin: CGFloat = 16
    /// Longer messages are shortened; a toast is a hint, the full text is in the log.
    static let maxCharacters = 600
    private static let fallbackSize = NSSize(width: maxWidth, height: 48)

    /// The view to show and the area it needs.
    @MainActor
    static func content(for message: String, isError: Bool) -> (view: NSView, size: NSSize) {
        let root = ToastView(message: limited(message), isError: isError)
        let measured = NSHostingController(rootView: root).sizeThatFits(in: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let size = usable(NSSize(width: ceil(measured.width), height: ceil(measured.height)))

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []   // the window decides the size, not SwiftUI
        hosting.frame = NSRect(origin: .zero, size: size)
        return (hosting, size)
    }

    static func limited(_ message: String) -> String {
        message.count > maxCharacters ? String(message.prefix(maxCharacters)) + "…" : message
    }

    /// A size the window can really have; anything else (zero, NaN, infinite) becomes a visible default.
    static func usable(_ size: NSSize) -> NSSize {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return fallbackSize }
        return NSSize(width: min(size.width, maxWidth), height: size.height)
    }

    /// Top-right corner of the usable area of a screen.
    static func origin(for size: NSSize, in area: NSRect) -> NSPoint {
        NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin)
    }
}
