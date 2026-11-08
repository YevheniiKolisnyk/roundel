import AppKit
import SwiftUI
import RoundelCore
@testable import Roundel

/// Real layouts from the default config, as view models, for rendering tests.
@MainActor
enum RingFixture {
    /// The writable formats of a typical Mac, so the generated "convert to" arc has its real eight cells.
    private struct Formats: ImageCapabilities {
        var writableTypeIdentifiers = ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp", "public.avif", "org.webmproject.webp"]
    }

    /// The default config with its generated groups filled in, exactly as the app builds the ring.
    static let nodes = ConfigResolver.resolve(DefaultConfig.config, generators: NodeGeneratorRegistry([ImageConvertFormatsGenerator(capabilities: Formats())])).config.ring

    /// The path to the format arc, and its eight labels in order.
    static let formatPath = ["files", "files.convert"]

    static func model(path: [String] = [], hover: RingItemRef? = nil, presented: Bool = true, placement: ArcPlacement.Context? = nil) -> RingModel {
        let layout = RingLayout.make(root: nodes, path: path, placement: placement)
        var levels: [[Node]] = [nodes]
        for id in path {
            guard let node = levels.last?.first(where: { $0.id == id }), let children = node.children else { break }
            levels.append(children)
        }
        let store = IconStore(baseDirectory: FileManager.default.temporaryDirectory)
        let model = RingModel()
        model.bands = layout.bands.map { band in
            let items = RingItem.items(for: levels[band.level], defaultIcon: { _ in .symbol("star.fill") }).map { DisplayItem(item: $0, icon: store.resolve($0)) }
            var connector: BandModel.Connector?
            if band.level > 0, let index = levels[band.level - 1].firstIndex(where: { $0.id == path[band.level - 1] }) {
                let parent = layout.bands[band.level - 1]
                connector = BandModel.Connector(angle: parent.centerAngle(ofItem: index), width: parent.itemWidth, innerRadius: parent.outerRadius, outerRadius: band.innerRadius, parentID: path[band.level - 1])
            }
            return BandModel(band: band, items: items, connector: connector)
        }
        model.hovered = hover
        model.openParents = Set(path.enumerated().compactMap { level, id in levels[level].firstIndex(where: { $0.id == id }).map { RingItemRef(level: level, index: $0) } })
        model.panelSide = RingMetrics.standard.panelSide(forOuterRadius: layout.outerRadius)
        model.footprint = layout.footprint
        model.isPresented = presented
        return model
    }

    /// A model that holds only the band at `level` of `full` (its connector kept): for looking at one arc on its own.
    static func only(level: Int, of full: RingModel) -> RingModel {
        let model = RingModel()
        model.bands = full.bands.filter { $0.band.level == level }
        model.panelSide = full.panelSide
        model.footprint = full.footprint
        model.isPresented = true
        return model
    }
}

/// An offscreen render read back as pixels.
struct Pixels {
    let width: Int, height: Int, scale: Double
    private let data: [UInt8]

    /// Renders `view` at `scale` (device pixels per point).
    @MainActor
    init?<V: View>(of view: V, scale: Double = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        width = image.width
        height = image.height
        self.scale = scale
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = bytes
    }

    /// Premultiplied RGBA of the pixel at (x, y), y counted from the top.
    func rgba(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        // CGContext memory is top-down for a context created this way and drawn into with the default (y-up) CTM:
        // row 0 is the top row of the image.
        let i = (y * width + x) * 4
        return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255, Double(data[i + 3]) / 255)
    }

    func alpha(atPointX x: Double, y: Double) -> Double {
        rgba(min(width - 1, max(0, Int(x * scale))), min(height - 1, max(0, Int(y * scale)))).a
    }
}
