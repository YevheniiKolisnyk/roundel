import XCTest
import AppKit
import SwiftUI
import RoundelCore
@testable import Roundel

/// The ring's shapes and its first frame. Nothing is shown on screen; shapes are probed as paths and the view is
/// rendered to an in-memory image.
@MainActor
final class RingViewTests: XCTestCase {
    private let style = RingStyle.standard
    private let rect = CGRect(x: 0, y: 0, width: 400, height: 400)
    private var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// A point in the ring's polar terms: angle clockwise from 12 o'clock.
    private func point(_ radius: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    // MARK: The band shape

    private func arc(corner: Double = 14) -> RingBandShape {
        RingBandShape(innerRadius: 120, outerRadius: 184, startAngle: -0.6, endAngle: 0.6, cornerRadius: corner)
    }

    func testABandContainsItsBodyAndNothingElse() {
        let path = arc().path(in: rect)
        XCTAssertTrue(path.contains(point(150, 0)))
        XCTAssertTrue(path.contains(point(130, 0.5)))
        XCTAssertTrue(path.contains(point(175, -0.5)))
        XCTAssertFalse(path.contains(center), "not the middle")
        XCTAssertFalse(path.contains(point(100, 0)), "inside the inner edge")
        XCTAssertFalse(path.contains(point(200, 0)), "beyond the outer edge")
        XCTAssertFalse(path.contains(point(150, 1.2)), "beyond its angular extent")
        XCTAssertFalse(path.contains(point(150, 3)), "the far side")
    }

    func testTheCornersAreRoundedNotSharp() {
        let sharp = arc(corner: 0).path(in: rect)
        let rounded = arc(corner: 14).path(in: rect)
        // The exact corner of the unrounded shape: the rounded one has cut it off, but is still full just inside.
        let corner = point(184 - 0.5, -0.6 + 0.5 / 184)
        XCTAssertTrue(sharp.contains(corner), "precondition: the sharp shape has this corner")
        XCTAssertFalse(rounded.contains(corner), "the rounded one does not")
        XCTAssertTrue(rounded.contains(point(184 - 8, -0.6 + 8 / 184)), "a little further in it is solid again")
        let innerCorner = point(120 + 0.5, 0.6 - 0.5 / 120)
        XCTAssertTrue(sharp.contains(innerCorner))
        XCTAssertFalse(rounded.contains(innerCorner))
    }

    func testRoundingNeverEatsTheMiddleOfAThinShape() {
        let thin = RingBandShape(innerRadius: 120, outerRadius: 130, startAngle: -0.05, endAngle: 0.05, cornerRadius: 40)   // radius far too big
        let path = thin.path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.contains(point(125, 0)))
    }

    func testAFullCircleBandIsARingWithAHole() {
        let ring = RingBandShape(innerRadius: 30, outerRadius: 130, startAngle: -.pi / 3, endAngle: -.pi / 3 + 2 * .pi, cornerRadius: 14, isFullCircle: true)
        let path = ring.path(in: rect)
        for angle in stride(from: 0.0, to: 2 * .pi, by: 0.5) { XCTAssertTrue(path.contains(point(80, angle)), "\(angle)") }
        XCTAssertFalse(path.contains(center), "the hole")
        XCTAssertFalse(path.contains(point(20, 1)), "still in the hole")
        XCTAssertFalse(path.contains(point(140, 1)), "outside")
    }

    func testInsettingShrinksTheShapeOnEverySide() {
        let inset = arc().inset(by: 6).path(in: rect)
        XCTAssertTrue(inset.contains(point(150, 0)))
        XCTAssertFalse(inset.contains(point(123, 0)), "6 points off the inner edge")
        XCTAssertFalse(inset.contains(point(181, 0)), "and off the outer edge")
        XCTAssertFalse(inset.contains(point(150, 0.6 - 2 / 150)), "and off the ends")
    }

    func testAShapeWithNoRoomIsEmptyNotBroken() {
        XCTAssertTrue(RingBandShape(innerRadius: 100, outerRadius: 100, startAngle: 0, endAngle: 1, cornerRadius: 5).path(in: rect).isEmpty)
        XCTAssertTrue(RingBandShape(innerRadius: 100, outerRadius: 150, startAngle: 1, endAngle: 1, cornerRadius: 5).path(in: rect).isEmpty)
        XCTAssertTrue(arc().inset(by: 500).path(in: rect).isEmpty)
    }

    // MARK: The first frame

    private func model() -> RingModel {
        let nodes: [Node] = (0..<6).map { .action(ActionNode(id: "n\($0)", title: "N\($0)", action: "log", params: .object([:]))) }
        let layout = RingLayout.make(root: nodes, path: [])
        let model = RingModel()
        model.bands = layout.bands.map { band in
            let items = RingItem.items(for: nodes, defaultIcon: { _ in .symbol("star.fill") }).map { DisplayItem(item: $0, icon: .symbol("star.fill")) }
            return BandModel(band: band, items: items, connector: nil)
        }
        model.panelSide = RingMetrics.standard.panelSide(forOuterRadius: layout.outerRadius)
        model.footprint = layout.footprint
        return model
    }

    /// Alpha (0-255) of the pixel at a ring offset (dx right, dy up from the center) in a render of the view at 1x.
    private func alpha(of model: RingModel, dx: Double, dy: Double) throws -> Int {
        let side = model.panelSide
        let renderer = ImageRenderer(content: RingView(model: model).frame(width: side, height: side).environment(\.colorScheme, .dark).environment(\.surfacePreference, .material))   // glass cannot be rendered offscreen; material is the same code path
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw the image so that the wanted pixel lands on the context's only pixel.
        let x = Double(image.width) / 2 + dx
        let yFromTop = Double(image.height) / 2 - dy
        context.draw(image, in: CGRect(x: -x, y: -(Double(image.height) - yFromTop), width: Double(image.width), height: Double(image.height)))
        return Int(pixel[3])
    }

    func testBeforeTheRingHasAppearedTheFootprintIsAlreadyThere() throws {
        let model = model()
        model.isPresented = false   // the first frame: the visual has not started to appear
        let band = model.bands[0].band
        let onTheRing = try alpha(of: model, dx: 0, dy: (band.innerRadius + band.outerRadius) / 2)
        XCTAssertGreaterThan(onTheRing, 0, "the window server has something to hit")
        XCTAssertLessThanOrEqual(onTheRing, 8, "but it is practically invisible")
        XCTAssertGreaterThan(try alpha(of: model, dx: 0, dy: 5), 0, "the dead zone belongs to the ring too")
        XCTAssertEqual(try alpha(of: model, dx: 0, dy: band.outerRadius + 20), 0, "outside the ring: clear, clicks go through")
    }

    func testOnceAppearedTheBandIsClearlyVisible() throws {
        let model = model()
        model.isPresented = true
        let band = model.bands[0].band
        XCTAssertGreaterThan(try alpha(of: model, dx: 0, dy: (band.innerRadius + band.outerRadius) / 2 - 15), 60)
    }

    func testAppearingDoesNotMoveTheFootprint() throws {
        let band = model().bands[0].band
        let radius = (band.innerRadius + band.outerRadius) / 2
        for presented in [false, true] {
            let model = model()
            model.isPresented = presented
            XCTAssertGreaterThan(try alpha(of: model, dx: radius * sin(1.0), dy: radius * cos(1.0)), 0, "presented \(presented)")
            XCTAssertEqual(try alpha(of: model, dx: 0, dy: band.outerRadius + 20), 0, "presented \(presented)")
        }
    }
}
