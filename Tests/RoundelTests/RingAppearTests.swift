import XCTest
import SwiftUI
import RoundelCore
@testable import Roundel

/// The ring and its arcs come in by opacity and a small scale of an already laid-out view; nothing else changes
/// between frames. Frames are rendered at fixed points of the animation (`RingView(frozen:)`) and compared with the
/// finished ring, scaled about its anchor and faded.
@MainActor
final class RingAppearTests: XCTestCase {
    private let style = RingStyle.standard

    private func render(_ model: RingModel, frozen: AppearFrame) throws -> Pixels {
        let side = model.panelSide
        let view = RingView(model: model, frozen: frozen)
            .frame(width: side, height: side)
            .environment(\.colorScheme, .dark)
            .environment(\.surfacePreference, .solid)   // glass cannot be rendered offscreen; solid is deterministic
        return try XCTUnwrap(Pixels(of: view, scale: 2))
    }

    /// `final` drawn the way the finished ring should look at `progress`: faded and scaled about `anchor` (points, y down).
    private func expected(from final: Pixels, side: Double, progress: Double, scale: Double, anchor: CGPoint) -> [Double] {
        let w = final.width, h = final.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var source = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let p = final.rgba(x, y); let i = (y * w + x) * 4
            source[i] = UInt8((p.r * 255).rounded()); source[i + 1] = UInt8((p.g * 255).rounded()); source[i + 2] = UInt8((p.b * 255).rounded()); source[i + 3] = UInt8((p.a * 255).rounded()) } }
        let image = source.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }!
        let ax = anchor.x * final.scale, ay = Double(h) - anchor.y * final.scale   // CG is y-up
        context.setAlpha(progress)
        context.interpolationQuality = .high
        context.translateBy(x: ax, y: ay)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -ax, y: -ay)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes.map { Double($0) / 255 }
    }

    /// Mean absolute difference per channel between a render and the expected bytes, over the pixels where either has
    /// anything (so a small arc on a big transparent panel is not averaged away).
    private func difference(_ pixels: Pixels, _ bytes: [Double]) -> Double {
        var total = 0.0
        var active = 0
        for y in 0..<pixels.height { for x in 0..<pixels.width {
            let p = pixels.rgba(x, y); let i = (y * pixels.width + x) * 4
            guard p.a > 0.05 || bytes[i + 3] > 0.05 else { continue }
            active += 1
            total += abs(p.r - bytes[i]) + abs(p.g - bytes[i + 1]) + abs(p.b - bytes[i + 2]) + abs(p.a - bytes[i + 3])
        } }
        return total / Double(max(1, active) * 4)
    }

    private let steps: [Double] = [0, 0.25, 0.5, 0.75, 1]   // t = 0, 30, 60, 90, 120 ms of a 150 ms ease-out, roughly

    func testTheRingFramesDifferFromTheFinishedRingOnlyByOpacityAndScale() throws {
        let model = RingFixture.model()
        let side = model.panelSide
        let final = try render(model, frozen: .init(ring: 1, arcs: 1))
        let center = CGPoint(x: side / 2, y: side / 2)
        for p in steps {
            let frame = try render(model, frozen: .init(ring: p, arcs: 1))
            let scale = style.appearScale + (1 - style.appearScale) * p
            let diff = difference(frame, expected(from: final, side: side, progress: p, scale: scale, anchor: center))
            XCTAssertLessThan(diff, 0.02, "ring frame at progress \(p)")
            if p > 0, p < 1 {
                // The check can fail: against an unscaled or shifted expectation the same frame is clearly different.
                let unscaled = difference(frame, expected(from: final, side: side, progress: p, scale: 1, anchor: center))
                let shifted = difference(frame, expected(from: final, side: side, progress: p, scale: scale, anchor: CGPoint(x: center.x + 6, y: center.y)))
                XCTAssertGreaterThan(max(unscaled, shifted), diff * 1.5, "progress \(p)")
            }
        }
    }

    func testAnArcFramesDifferFromTheFinishedArcOnlyByOpacityAndScaleAboutTheParentsAnchor() throws {
        let full = RingFixture.model(path: ["launch"])
        let arcOnly = RingFixture.only(level: 1, of: full)
        let side = full.panelSide
        let connector = try XCTUnwrap(arcOnly.bands[0].connector)
        let anchor = CGPoint(x: side / 2 + connector.outerRadius * sin(connector.angle), y: side / 2 - connector.outerRadius * cos(connector.angle))
        let final = try render(arcOnly, frozen: .init(ring: 1, arcs: 1))
        for p in steps {
            let frame = try render(arcOnly, frozen: .init(ring: 1, arcs: p))
            let scale = style.arcAppearScale + (1 - style.arcAppearScale) * p
            if p == 0 {
                // Not started: the arc is not there (the small center mark that belongs to the root band is, in this one-band model).
                let r = (arcOnly.bands[0].band.innerRadius + arcOnly.bands[0].band.outerRadius) / 2
                let a = arcOnly.bands[0].band.centerAngle(ofItem: 0)
                XCTAssertLessThan(frame.alpha(atPointX: side / 2 + r * sin(a), y: side / 2 - r * cos(a)), 0.05)
                continue
            }
            XCTAssertLessThan(difference(frame, expected(from: final, side: side, progress: p, scale: scale, anchor: anchor)), 0.02, "arc frame at progress \(p)")
        }
    }

    func testTheLayoutIsFinalFromTheFirstFrame() throws {
        // Whatever the progress, the model that describes positions and sizes is the same object state: appearing never
        // writes to it, and the footprint (the click area) is identical at every frame.
        let model = RingFixture.model(path: ["launch"])
        let before = (model.panelSide, model.footprint, model.bands.map(\.band))
        var alphas: [[Double]] = []
        for p in steps {
            let pixels = try render(model, frozen: .init(ring: p, arcs: p))
            alphas.append([(model.bands[0].band.innerRadius + model.bands[0].band.outerRadius) / 2].map { r in pixels.alpha(atPointX: model.panelSide / 2, y: model.panelSide / 2 - r) })
        }
        XCTAssertEqual(before.0, model.panelSide)
        XCTAssertEqual(before.1, model.footprint)
        XCTAssertEqual(before.2, model.bands.map(\.band))
        XCTAssertTrue(alphas.allSatisfy { $0[0] > 0 }, "the click area is there at every frame, even at progress 0")
    }

    func testReduceMotionOnlyFadesNothingScales() throws {
        var overrides = SurfaceOverrides(); overrides.reduceMotion = true
        let model = RingFixture.model()
        let side = model.panelSide
        let render = { (p: Double) throws -> Pixels in
            try XCTUnwrap(Pixels(of: RingView(model: model, frozen: .init(ring: p, arcs: p)).frame(width: side, height: side)
                .environment(\.colorScheme, .dark).environment(\.surfacePreference, .solid).environment(\.surfaceOverrides, overrides)))
        }
        let final = try render(1)
        let half = try render(0.5)
        let diff = difference(half, expected(from: final, side: side, progress: 0.5, scale: 1, anchor: CGPoint(x: side / 2, y: side / 2)))
        XCTAssertLessThan(diff, 0.02)
    }
}
