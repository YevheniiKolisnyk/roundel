import XCTest
@testable import RoundelCore

/// Which kind of surface everything is drawn on: Liquid Glass, a Material, or a solid color.
final class SurfaceStyleTests: XCTestCase {
    func testGlassWhereTheSystemHasIt() {
        XCTAssertEqual(SurfaceStyle.resolve(preference: .automatic, glassAvailable: true, reduceTransparency: false), .glass)
    }

    func testMaterialOnSystemsWithoutGlass() {
        XCTAssertEqual(SurfaceStyle.resolve(preference: .automatic, glassAvailable: false, reduceTransparency: false), .material)
    }

    func testReduceTransparencyAlwaysWinsAndGivesASolidSurface() {
        for preference in [SurfacePreference.automatic, .glass, .material, .solid] {
            for glass in [true, false] {
                XCTAssertEqual(SurfaceStyle.resolve(preference: preference, glassAvailable: glass, reduceTransparency: true), .solid, "\(preference) \(glass)")
            }
        }
    }

    func testTheSolidPreferenceGivesTheSameLookAsReduceTransparency() {
        XCTAssertEqual(SurfaceStyle.resolve(preference: .solid, glassAvailable: true, reduceTransparency: false),
                       SurfaceStyle.resolve(preference: .automatic, glassAvailable: true, reduceTransparency: true))
    }

    func testTheMaterialPreferenceForcesMaterialEvenWhereGlassExists() {
        XCTAssertEqual(SurfaceStyle.resolve(preference: .material, glassAvailable: true, reduceTransparency: false), .material)
    }

    func testAskingForGlassWithoutGlassFallsBackToMaterial() {
        XCTAssertEqual(SurfaceStyle.resolve(preference: .glass, glassAvailable: false, reduceTransparency: false), .material)
        XCTAssertEqual(SurfaceStyle.resolve(preference: .glass, glassAvailable: true, reduceTransparency: false), .glass)
    }

    /// The Material look on macOS 14-15 and the one forced with ROUNDEL_SURFACE=material on a newer system are the same
    /// resolved style, so the switch exercises exactly what an older system will show.
    func testTheForcedMaterialPathIsTheSamePathAsAnOlderSystem() {
        XCTAssertEqual(SurfaceStyle.resolve(preference: .automatic, glassAvailable: false, reduceTransparency: false),
                       SurfaceStyle.resolve(preference: .material, glassAvailable: true, reduceTransparency: false))
    }

    // MARK: ROUNDEL_SURFACE

    func testThePreferenceIsReadFromTheEnvironmentValue() {
        XCTAssertEqual(SurfacePreference.parse("material"), .material)
        XCTAssertEqual(SurfacePreference.parse("solid"), .solid)
        XCTAssertEqual(SurfacePreference.parse("glass"), .glass)
        XCTAssertEqual(SurfacePreference.parse("  Material \n"), .material, "case and whitespace do not matter")
        XCTAssertEqual(SurfacePreference.parse("SOLID"), .solid)
    }

    func testAnythingElseMeansAutomatic() {
        XCTAssertEqual(SurfacePreference.parse(nil), .automatic)
        XCTAssertEqual(SurfacePreference.parse(""), .automatic)
        XCTAssertEqual(SurfacePreference.parse("auto"), .automatic)
        XCTAssertEqual(SurfacePreference.parse("frosted"), .automatic)
    }

    // MARK: Traits

    func testIncreasedContrastMakesBordersAndSecondaryTextStronger() {
        for style in [SurfaceStyle.glass, .material, .solid] {
            let normal = SurfaceTraits.make(style: style, increaseContrast: false)
            let strong = SurfaceTraits.make(style: style, increaseContrast: true)
            XCTAssertGreaterThan(strong.borderWidth, normal.borderWidth, "\(style)")
            XCTAssertGreaterThan(strong.borderOpacity, normal.borderOpacity, "\(style)")
            XCTAssertGreaterThan(strong.secondaryTextOpacity, normal.secondaryTextOpacity, "\(style)")
        }
    }

    func testASolidSurfaceNeedsAClearerEdgeThanATranslucentOne() {
        let solid = SurfaceTraits.make(style: .solid, increaseContrast: false)
        let material = SurfaceTraits.make(style: .material, increaseContrast: false)
        XCTAssertGreaterThan(solid.borderOpacity, material.borderOpacity, "no blur to separate it from what is behind")
    }

    func testOpacitiesAreValid() {
        for style in [SurfaceStyle.glass, .material, .solid] {
            for contrast in [true, false] {
                let t = SurfaceTraits.make(style: style, increaseContrast: contrast)
                XCTAssertTrue((0...1).contains(t.borderOpacity) && (0...1).contains(t.secondaryTextOpacity))
                XCTAssertGreaterThan(t.borderWidth, 0)
            }
        }
    }
}
