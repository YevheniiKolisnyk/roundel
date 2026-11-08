import XCTest
@testable import RoundelCore

/// The larger arcs (68 pt cells, 76 pt thick; was 44 and 64): the click footprint still covers all of them, nested arcs
/// stay apart, the default config still fits, and sliding an arc along its band at a screen edge still picks the best spot.
final class RingArcGeometryTests: XCTestCase {
    private let metrics = RingMetrics.standard

    private func action(_ id: String) -> Node { .action(ActionNode(id: id, title: id, action: "log")) }
    private func group(_ id: String, _ children: [Node]) -> Node { .group(GroupNode(id: id, title: id, children: children)) }
    private func actions(_ count: Int, prefix: String = "c") -> [Node] { (0..<count).map { action("\(prefix)\($0)") } }

    /// Root of six sections with "g" first, holding `count` children, one of which ("n", the last) holds `inner` more.
    private func nested(_ count: Int, inner: Int, deeper: Int = 0) -> [Node] {
        let innermost: [Node] = deeper > 0 ? [group("m", actions(deeper, prefix: "m"))] + actions(inner - 1, prefix: "k") : actions(inner, prefix: "k")
        return [group("g", actions(count - 1) + [group("n", innermost)])] + actions(5, prefix: "r")
    }

    private func polar(_ radius: Double, _ angle: Double) -> (dx: Double, dy: Double) { (radius * sin(angle), radius * cos(angle)) }

    // MARK: The footprint covers the whole arc

    func testTheFootprintCoversEveryPointOfEveryArcAndTheGapToItsParent() {
        for count in [1, 3, 5, 8, 12, 20] {
            for path in [["g"], ["g", "n"]] {
                let layout = RingLayout.make(root: nested(count, inner: count), path: path)
                for band in layout.bands where band.level > 0 {
                    let previousOuter = layout.bands[band.level - 1].outerRadius
                    let start = band.startAngle, end = band.startAngle + band.sweep
                    for step in 0...40 {
                        let angle = start + (end - start) * (0.0005 + 0.999 * Double(step) / 40)   // not exactly on the end lines: floating point decides those
                        for radius in stride(from: previousOuter + 0.25, through: band.outerRadius - 0.25, by: 1.5) {
                            let p = polar(radius, angle)
                            XCTAssertTrue(layout.footprintContains(dx: p.dx, dy: p.dy), "count \(count) path \(path) level \(band.level) r \(radius) angle \(angle)")
                        }
                    }
                    // Just beyond the outer edge, and a little past either end of the arc, the ring owns nothing.
                    let beyond = polar(band.outerRadius + 1, (start + end) / 2)
                    XCTAssertFalse(layout.bands.last.map { $0.level == band.level } == true && layout.footprintContains(dx: beyond.dx, dy: beyond.dy), "outside the outermost band")
                    if band.sweep < 2 * .pi - 0.5 {
                        let past = polar((band.innerRadius + band.outerRadius) / 2, start - 0.05)
                        XCTAssertFalse(layout.footprintContains(dx: past.dx, dy: past.dy), "click-through past the arc's end")
                    }
                }
            }
        }
    }

    func testTheFootprintIsDerivedFromTheNewBandSizes() {
        let layout = RingLayout.make(root: nested(8, inner: 4), path: ["g"])
        let arc = layout.bands[1]
        XCTAssertEqual(arc.outerRadius - arc.innerRadius, 76, accuracy: 1e-9)
        XCTAssertEqual(layout.footprint[1].outerRadius, arc.outerRadius)
        XCTAssertEqual(layout.footprint[1].innerRadius, layout.bands[0].outerRadius)
        XCTAssertEqual(layout.footprint[1].sweep, arc.sweep, accuracy: 1e-12)
    }

    // MARK: Nesting

    func testNestedArcsAreSeparatedByTheGapAndNeverMeetTheRootOrEachOther() {
        let layout = RingLayout.make(root: nested(8, inner: 8, deeper: 6), path: ["g", "n", "m"])
        XCTAssertEqual(layout.bands.count, 4)
        for i in 1..<layout.bands.count {
            XCTAssertEqual(layout.bands[i].innerRadius, layout.bands[i - 1].outerRadius + metrics.bandGap, accuracy: 1e-9, "level \(i)")
            XCTAssertGreaterThan(layout.bands[i].innerRadius, layout.bands[i - 1].outerRadius, "no overlap")
            XCTAssertEqual(layout.bands[i].outerRadius - layout.bands[i].innerRadius, metrics.bandThickness, accuracy: 1e-9)
        }
        XCTAssertFalse(layout.bands.contains { $0.exceedsRadiusCap }, "three arcs out of a 124 pt root fit the cap")
        XCTAssertLessThanOrEqual(layout.outerRadius, metrics.arcRadiusCap + 1e-9)
    }

    func testAFourthArcOutIsStillFlaggedAsTooDeep() {
        let deep: [Node] = [group("a", [group("b", [group("c", [group("d", actions(3))])])]), action("x")]
        let warnings = metrics.levelWarnings(in: RoundelConfig(ring: deep))
        XCTAssertEqual(warnings.map(\.kind), [.tooDeep])
        XCTAssertEqual(warnings.first?.path, ["a", "b", "c", "d"])
    }

    private struct Formats: ImageCapabilities {
        var writableTypeIdentifiers = ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp", "public.avif", "org.webmproject.webp"]
    }

    func testTheDefaultConfigHasNoCrowdedOrTooDeepLevelWithTheLargerArcs() {
        let resolved = ConfigResolver.resolve(DefaultConfig.config, generators: NodeGeneratorRegistry([ImageConvertFormatsGenerator(capabilities: Formats())])).config
        XCTAssertEqual(metrics.levelWarnings(in: resolved), [])
        // And the deepest path of it fits the usable height of a small laptop screen (1280 x 720 minus menu bar and Dock).
        let layout = RingLayout.make(root: resolved.ring, path: ["files", "files.convert"])
        XCTAssertLessThanOrEqual(layout.outerRadius + metrics.panelPadding, 695.0 / 2, "\(layout.outerRadius)")
    }

    // MARK: Screen edges

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private func overflow(of band: RingBand, center: CGPoint, bounds: CGRect) -> Double {
        let safe = bounds.insetBy(dx: metrics.edgeMargin, dy: metrics.edgeMargin)
        var total = 0.0
        for radius in [band.innerRadius, band.outerRadius] {
            for step in 0...20 {
                let angle = band.startAngle + band.sweep * Double(step) / 20
                let x = Double(center.x) + radius * sin(angle), y = Double(center.y) + radius * cos(angle)
                total += max(0, Double(safe.minX) - x) + max(0, x - Double(safe.maxX)) + max(0, Double(safe.minY) - y) + max(0, y - Double(safe.maxY))
            }
        }
        return total
    }

    func testAtEveryEdgeAndCornerThePlacementPicksTheLeastOverflowOfTheBiggerArc() {
        let centers = [CGPoint(x: 720, y: 437), CGPoint(x: 60, y: 437), CGPoint(x: 1380, y: 437), CGPoint(x: 720, y: 60), CGPoint(x: 720, y: 815),
                       CGPoint(x: 60, y: 60), CGPoint(x: 1380, y: 60), CGPoint(x: 60, y: 815), CGPoint(x: 1380, y: 815)]
        // The root has six sections (60 degrees each), so every parent direction in turn.
        for center in centers {
            for parent in 0..<6 {
                var root = actions(5, prefix: "r")
                root.insert(group("g", actions(8)), at: parent)
                let layout = RingLayout.make(root: root, path: ["g"], placement: ArcPlacement.Context(ringCenter: center, bounds: screen))
                let arc = layout.bands[1]
                let chosen = overflow(of: arc, center: center, bounds: screen)

                // Brute force over every allowed centre angle (the parent must stay inside the arc).
                let parentAngle = layout.bands[0].centerAngle(ofItem: parent)
                let free = RingLayout.make(root: root, path: ["g"]).bands[1]
                let maxShift = max(0, free.sweep / 2 - free.itemWidth / 2)
                var best = Double.infinity
                for k in stride(from: -maxShift, through: maxShift, by: 0.005) {
                    let shifted = RingBand(level: 1, innerRadius: free.innerRadius, outerRadius: free.outerRadius, startAngle: parentAngle + k - free.sweep / 2,
                                           itemWidth: free.itemWidth, count: free.count, iconRadius: free.iconRadius, iconSize: free.iconSize, isCrowded: free.isCrowded)
                    best = min(best, overflow(of: shifted, center: center, bounds: screen))
                }
                XCTAssertLessThanOrEqual(chosen, best + 1.0, "center \(center) parent \(parent): placement chose \(chosen), best possible \(best)")
            }
        }
    }

    func testAnArcThatFitsAtTheCenterOfTheScreenIsNotMovedAtAll() {
        let center = CGPoint(x: 720, y: 437)
        for parent in 0..<6 {
            var root = actions(5, prefix: "r")
            root.insert(group("g", actions(8)), at: parent)
            let placed = RingLayout.make(root: root, path: ["g"], placement: ArcPlacement.Context(ringCenter: center, bounds: screen)).bands[1]
            let free = RingLayout.make(root: root, path: ["g"]).bands[1]
            XCTAssertEqual(placed.startAngle, free.startAngle, accuracy: 1e-9, "parent \(parent)")
        }
    }
}
