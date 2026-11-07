import AppKit
import RoundelCore

/// How one node icon is actually drawn, resolved once per level (not per frame).
enum ResolvedIcon {
    case symbol(String)
    case emoji(String)
    case image(NSImage)
    case letter(String)
}

/// Loads custom images (paths relative to the config folder) when a config is applied, so opening the ring
/// never touches the disk. Missing files and unknown SF Symbols are logged and fall back to the first letter.
@MainActor
final class IconStore {
    private let baseDirectory: URL
    private var images: [String: NSImage] = [:]
    private static let maxPixels = 96

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory.standardizedFileURL
    }

    func reload(for config: RoundelConfig) {
        var loaded: [String: NSImage] = [:]
        visit(config.ring) { node in
            switch node.icon {
            case .image(let path)?:
                guard loaded[path] == nil else { return }
                if let image = load(relativePath: path) {
                    loaded[path] = image
                } else {
                    Log.warning("Icon image for '\(node.id)' not found or unreadable: \(path) (showing the first letter instead)")
                }
            case .symbol(let name)?:
                if NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
                    Log.warning("Unknown SF Symbol '\(name)' for '\(node.id)' (showing the first letter instead)")
                }
            default:
                break
            }
        }
        images = loaded
    }

    func resolve(_ item: RingItem) -> ResolvedIcon {
        let letter = ResolvedIcon.letter(RingItem.fallbackLetter(for: item.title))
        switch item.icon {
        case .symbol(let name)?:
            return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? .symbol(name) : letter
        case .emoji(let value)?:
            return .emoji(value)
        case .text(let value)?:
            return .letter(value)
        case .image(let path)?:
            return images[path].map(ResolvedIcon.image) ?? letter
        case nil:
            return letter
        }
    }

    // MARK: Private

    private func visit(_ nodes: [Node], _ body: (Node) -> Void) {
        for node in nodes {
            body(node)
            if let children = node.children { visit(children, body) }
        }
    }

    private func load(relativePath: String) -> NSImage? {
        let url = baseDirectory.appendingPathComponent(relativePath).standardizedFileURL
        // The decoder already rejects escaping paths; this is the belt to that pair of braces.
        guard url.path.hasPrefix(baseDirectory.path + "/"),
              let image = NSImage(contentsOf: url) else { return nil }
        return Self.downscaled(image)
    }

    /// Pre-render large images to at most `maxPixels` so drawing the ring stays cheap.
    private static func downscaled(_ image: NSImage) -> NSImage {
        let pixelSize = image.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > CGFloat(maxPixels), longest > 0 else { return image }

        let scale = CGFloat(maxPixels) / longest
        let width = max(1, Int((pixelSize.width * scale).rounded()))
        let height = max(1, Int((pixelSize.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: NSSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2))
        result.addRepresentation(rep)
        return result
    }
}
