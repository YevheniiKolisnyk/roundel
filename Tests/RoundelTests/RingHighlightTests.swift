import XCTest
import SwiftUI
import RoundelCore
@testable import Roundel

/// The selected cell's silhouette: a clean rounded sector, inside its band, with nothing blurred or spilling outside.
@MainActor
final class RingHighlightTests: XCTestCase {
    private let style = RingStyle.standard

    private func shape(_ g: HighlightGeometry) -> RingBandShape {
        RingBandShape(innerRadius: g.innerRadius, outerRadius: g.outerRadius, startAngle: g.startAngle, endAngle: g.endAngle, cornerRadius: g.cornerRadius)
    }

    /// Root cells of rings of different sizes, and arc cells of different counts, near the start, middle and end.
    private func cases() -> [(name: String, band: RingBand, index: Int)] {
        var result: [(String, RingBand, Int)] = []
        for count in [3, 6, 11] {
            let band = RingLayout.make(root: Array(RingFixture.nodes.prefix(1)) + [], path: []).bands[0]
            _ = band
            let nodes = (0..<count).map { Node.action(ActionNode(id: "n\($0)", title: "N", action: "log", params: .object([:]))) }
            let root = RingLayout.make(root: nodes, path: []).bands[0]
            for index in Set([0, count / 2, count - 1]) { result.append(("root \(count) #\(index)", root, index)) }
        }
        for count in [2, 5, 9] {
            let group = Node.group(GroupNode(id: "g", title: "G", icon: nil, children: (0..<count).map { .action(ActionNode(id: "c\($0)", title: "C", action: "log", params: .object([:]))) }))
            for placement in [nil, ArcPlacement.Context(ringCenter: CGPoint(x: 40, y: 450), bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))] {
                let arc = RingLayout.make(root: [group] + (1..<6).map { .action(ActionNode(id: "x\($0)", title: "X", action: "log", params: .object([:]))) }, path: ["g"], placement: placement).bands[1]
                for index in Set([0, count / 2, count - 1]) { result.append(("arc \(count) #\(index) \(placement == nil ? "free" : "edge")", arc, index)) }
            }
        }
        return result
    }

    func testTheHighlightLiesEntirelyInsideItsBand() {
        for (name, band, index) in cases() {
            let g = style.highlightGeometry(for: band, index: index)
            let highlight = shape(g).path(in: CGRect(x: 0, y: 0, width: 600, height: 600))
            let bandPath = RingBandShape.of(band, style: style).path(in: CGRect(x: 0, y: 0, width: 600, height: 600))
            XCTAssertFalse(highlight.isEmpty, name)
            var checked = 0
            for x in stride(from: 0.0, to: 600, by: 3) {
                for y in stride(from: 0.0, to: 600, by: 3) {
                    let p = CGPoint(x: x, y: y)
                    if highlight.contains(p) {
                        checked += 1
                        if !bandPath.contains(p) { return XCTFail("\(name): a highlight point (\(x), \(y)) is outside the band") }
                    }
                }
            }
            XCTAssertGreaterThan(checked, 20, name)
        }
    }

    func testNothingIsDrawnOutsideTheSectorAndItsInsideIsSolid() throws {
        let side = 600.0
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        for (name, band, index) in cases() {
            for dark in [false, true] {
                for contrast in [false, true] {
                    var overrides = SurfaceOverrides(); overrides.increaseContrast = contrast
                    let g = style.highlightGeometry(for: band, index: index)
                    let view = ItemHighlight(geometry: g, emphasis: .hovered, side: side)
                        .frame(width: side, height: side)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.surfaceOverrides, overrides)
                    let pixels = try XCTUnwrap(Pixels(of: view), name)
                    let path = shape(g).path(in: rect)
                    let tolerant = path.strokedPath(StrokeStyle(lineWidth: 2))   // one point of anti-aliasing on each side
                    var stray = 0
                    for y in 0..<pixels.height {
                        for x in 0..<pixels.width where pixels.rgba(x, y).a > 0.03 {
                            let p = CGPoint(x: (Double(x) + 0.5) / pixels.scale, y: (Double(y) + 0.5) / pixels.scale)
                            if !path.contains(p) && !tolerant.contains(p) { stray += 1 }
                        }
                    }
                    XCTAssertEqual(stray, 0, "\(name) dark \(dark) contrast \(contrast): pixels outside the sector")
                    // Inside, away from the rim, it is filled with the accent, not see-through and not blurry-thin.
                    let core = shape(g).inset(by: 5).path(in: rect)
                    var inside = 0, solid = 0
                    for x in stride(from: 0.0, to: side, by: 4) {
                        for y in stride(from: 0.0, to: side, by: 4) where core.contains(CGPoint(x: x, y: y)) {
                            inside += 1
                            if pixels.alpha(atPointX: x, y: y) >= 0.6 { solid += 1 }
                        }
                    }
                    XCTAssertGreaterThan(inside, 0, name)
                    XCTAssertEqual(solid, inside, "\(name) dark \(dark) contrast \(contrast): the inside is solid")
                }
            }
        }
    }

    func testTheHighlightHasNoHardBlurOnItsEdge() throws {
        // Across the outline the alpha must go from solid to clear within about a point: no soft halo.
        let side = 600.0
        let (name, band, index) = cases()[4]
        let g = style.highlightGeometry(for: band, index: index)
        let view = ItemHighlight(geometry: g, emphasis: .hovered, side: side).frame(width: side, height: side).environment(\.colorScheme, .dark)
        let pixels = try XCTUnwrap(Pixels(of: view), name)
        let mid = (g.startAngle + g.endAngle) / 2
        // Walk outwards along the middle of the cell, across the outer rim.
        var firstClear: Double?
        var lastSolid = 0.0
        for step in 0...80 {
            let r = g.outerRadius - 8 + Double(step) * 0.2
            let a = pixels.alpha(atPointX: side / 2 + r * sin(mid), y: side / 2 - r * cos(mid))
            if a >= 0.6 { lastSolid = r }
            if a < 0.05, firstClear == nil { firstClear = r }
        }
        let fall = (firstClear ?? 99) - lastSolid
        XCTAssertLessThanOrEqual(fall, 1.5, "from solid to clear over \(fall) pt")
    }
}
