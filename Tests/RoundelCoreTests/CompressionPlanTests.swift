import XCTest
@testable import RoundelCore

/// What is done with a file, decided from facts about it (pure).
final class CompressionPlanTests: XCTestCase {
    private func facts(_ type: String, animated: Bool = false, aux: Bool = false, ijg: Int? = nil, webpLossless: Bool? = nil) -> ImageFacts {
        ImageFacts(detectedType: type, isAnimated: animated, hasAuxiliaryData: aux, jpegQualityIJG: ijg, webpIsLossless: webpLossless)
    }
    private func decide(_ f: ImageFacts, _ o: CompressionOptions = CompressionOptions()) -> CompressionDecision { CompressionPlan.decide(f, options: o) }
    private func options(_ preset: CompressionPreset, quality: Double? = nil, maxDimension: Int? = nil, strip: Bool = false) -> CompressionOptions {
        CompressionOptions(preset: preset, quality: quality, maxDimension: maxDimension, stripMetadata: strip)
    }

    // MARK: Presets

    func testThePresetNumbers() {
        XCTAssertEqual(CompressionPreset.allCases.map(\.jpegQuality), [0.70, 0.55, 0.40])
        XCTAssertEqual(CompressionPreset.allCases.map(\.heicQuality), [0.65, 0.55, 0.45])
        XCTAssertEqual(CompressionPreset.allCases.map(\.webpQuality), [0.80, 0.70, 0.55])
        XCTAssertEqual(CompressionPreset.allCases.map(\.title), ["Light", "Balanced", "Strong"])
        XCTAssertEqual(CompressionPreset.allCases.map(\.rawValue), ["light", "balanced", "strong"])
    }

    func testPresetsGetStrongerNotWeaker() {
        for (a, b) in zip(CompressionPreset.allCases, CompressionPreset.allCases.dropFirst()) {
            XCTAssertGreaterThan(a.jpegQuality, b.jpegQuality); XCTAssertGreaterThan(a.heicQuality, b.heicQuality); XCTAssertGreaterThan(a.webpQuality, b.webpQuality)
        }
    }

    func testOptionsFromParams() {
        XCTAssertEqual(CompressionOptions(params: Params(.object([:]))), CompressionOptions(preset: .balanced, quality: nil, maxDimension: nil, stripMetadata: false), "balanced by default")
        let full = Params(.object(["preset": .string("strong"), "quality": .number(0.3), "maxDimension": .number(2048), "stripMetadata": .bool(true)]))
        XCTAssertEqual(CompressionOptions(params: full), CompressionOptions(preset: .strong, quality: 0.3, maxDimension: 2048, stripMetadata: true))
        XCTAssertEqual(CompressionOptions(params: Params(.object(["preset": .string("nonsense")]))).preset, .balanced)
    }

    // MARK: PNG

    func testPNGGoesToTheOptimizerWithEffortFromThePreset() {
        XCTAssertEqual(decide(facts("public.png"), options(.light)), .optimizePNG(.init(effort: .light, stripMetadata: false)))
        for preset in [CompressionPreset.balanced, .strong] {
            XCTAssertEqual(decide(facts("public.png"), options(preset)), .optimizePNG(.init(effort: .thorough, stripMetadata: false)), "Strong is Balanced for PNG")
        }
        XCTAssertEqual(decide(facts("public.png"), options(.balanced, quality: 0.1, strip: true)), .optimizePNG(.init(effort: .thorough, stripMetadata: true)), "a quality never makes PNG lossy")
    }

    func testAnimatedPNGIsSkipped() {
        XCTAssertEqual(decide(facts("public.png", animated: true)), .skip(.animated))
    }

    // MARK: JPEG

    func testJPEGUsesThePresetQualityWhenTheSourceHasRoom() {
        guard case .reencode(let format, let o) = decide(facts("public.jpeg", ijg: 96), options(.balanced)) else { return XCTFail("re-encode") }
        XCTAssertEqual(format.key, "jpeg")
        XCTAssertEqual(o.quality, 0.55)
        XCTAssertFalse(o.lossless)
    }

    func testJPEGQualityIsCappedBelowTheSourcesSoTheFileCannotGrow() throws {
        // A source at IJG 80 (ImageIO 0.5): Light (0.70, IJG 92) would only make it bigger, so it is lowered.
        guard case .reencode(_, let o) = decide(facts("public.jpeg", ijg: 80), options(.light)) else { return XCTFail("re-encode") }
        let quality = try XCTUnwrap(o.quality)
        XCTAssertLessThan(quality, 0.70)
        XCTAssertLessThanOrEqual(JPEGQuality.ijg(forImageIO: quality), 80 - 4 + 0.5, "four IJG points below the source")
        // A preset that is already lower than the cap is left alone.
        guard case .reencode(_, let strong) = decide(facts("public.jpeg", ijg: 96), options(.strong)) else { return XCTFail("re-encode") }
        XCTAssertEqual(strong.quality, 0.40)
    }

    func testAJPEGThatIsAlreadyHeavilyCompressedIsAlreadyOptimal() {
        XCTAssertEqual(decide(facts("public.jpeg", ijg: 45), options(.balanced)), .alreadyOptimal)
        // ... unless a size limit gives something to do.
        guard case .reencode = decide(facts("public.jpeg", ijg: 45), options(.balanced, maxDimension: 1024)) else { return XCTFail("resizing is worth it") }
    }

    func testAnExplicitQualityIsUsedAsGivenWithoutTheCap() {
        guard case .reencode(_, let o) = decide(facts("public.jpeg", ijg: 60), options(.balanced, quality: 0.9)) else { return XCTFail("re-encode") }
        XCTAssertEqual(o.quality, 0.9)
    }

    func testAJPEGWhoseQualityCannotBeEstimatedGetsThePreset() {
        guard case .reencode(_, let o) = decide(facts("public.jpeg", ijg: nil), options(.light)) else { return XCTFail("re-encode") }
        XCTAssertEqual(o.quality, 0.70)
    }

    func testMaxDimensionStripAndThoroughnessArePassedOn() {
        guard case .reencode(_, let o) = decide(facts("public.jpeg", ijg: 95), options(.balanced, maxDimension: 2048, strip: true)) else { return XCTFail() }
        XCTAssertEqual(o.maxDimension, 2048)
        XCTAssertTrue(o.stripMetadata)
    }

    // MARK: HEIC, WebP

    func testHEICUsesItsOwnQualities() {
        for preset in CompressionPreset.allCases {
            guard case .reencode(let format, let o) = decide(facts("public.heic"), options(preset)) else { return XCTFail("re-encode") }
            XCTAssertEqual(format.key, "heic")
            XCTAssertEqual(o.quality, preset.heicQuality)
        }
    }

    func testLossyWebPIsReEncodedLossyAndLosslessWebPStaysLossless() {
        guard case .reencode(let lossyFormat, let lossy) = decide(facts("org.webmproject.webp", webpLossless: false), options(.balanced)) else { return XCTFail() }
        XCTAssertEqual(lossyFormat.key, "webp"); XCTAssertEqual(lossy.quality, 0.70); XCTAssertFalse(lossy.lossless)
        guard case .reencode(_, let lossless) = decide(facts("org.webmproject.webp", webpLossless: true), options(.strong)) else { return XCTFail() }
        XCTAssertTrue(lossless.lossless, "never silently becomes lossy")
        XCTAssertEqual(lossless.quality, 1.0, "maximum effort: nothing visible changes")
    }

    func testAWebPWhoseKindIsUnknownIsLeftAlone() {
        XCTAssertEqual(decide(facts("org.webmproject.webp", webpLossless: nil)), .skip(.unsupported("WebP")))
    }

    func testHDRDepthAndLivePhotoDataMeansSkipped() {
        for type in ["public.heic", "public.jpeg"] {
            XCTAssertEqual(decide(facts(type, aux: true, ijg: 95)), .skip(.hasAuxiliaryData), type)
        }
    }

    // MARK: Everything else

    func testAnimatedFilesAreSkippedWhateverTheirFormat() {
        for type in ["com.compuserve.gif", "public.heics", "org.webmproject.webp", "public.png"] {
            XCTAssertEqual(decide(facts(type, animated: true, webpLossless: true)), .skip(.animated), type)
        }
    }

    func testOtherFormatsPointToConvert() {
        XCTAssertEqual(decide(facts("com.compuserve.gif")), .skip(.useConvert("GIF")))
        XCTAssertEqual(decide(facts("com.microsoft.bmp")), .skip(.useConvert("BMP")))
        XCTAssertEqual(decide(facts("public.tiff")), .skip(.useConvert("TIFF")))
        XCTAssertEqual(decide(facts("public.avif")), .skip(.useConvert("AVIF")))
        XCTAssertEqual(decide(facts("com.adobe.photoshop-image")), .skip(.unsupported("PSD")))
        XCTAssertEqual(decide(facts("public.some-unknown")), .skip(.unsupported("public.some-unknown")))
    }

    func testTheWordsTheUserSees() {
        XCTAssertEqual(CompressionSkipReason.animated.message, "animated, skipped (compressing would drop the animation)")
        XCTAssertEqual(CompressionSkipReason.useConvert("GIF").message, "GIF isn’t compressed; use Convert to WebP")
        XCTAssertEqual(CompressionSkipReason.hasAuxiliaryData.message, "has HDR, depth or Live Photo data, skipped (re-encoding would drop it)")
        XCTAssertEqual(CompressionSkipReason.interlacedPNG.message, "interlaced PNG, skipped")
        XCTAssertEqual(CompressionSkipReason.unsupported("PSD").message, "PSD isn’t supported")
    }

    // MARK: Output extension

    func testTheOutputExtensionFollowsTheContent() {
        let url: (String) -> URL = { URL(fileURLWithPath: "/tmp/\($0)") }
        XCTAssertEqual(CompressionPlan.outputExtension(detectedType: "public.jpeg", source: url("a.jpg")), "jpg")
        XCTAssertEqual(CompressionPlan.outputExtension(detectedType: "public.jpeg", source: url("a.JPEG")), "JPEG", "a right extension keeps its spelling")
        XCTAssertEqual(CompressionPlan.outputExtension(detectedType: "public.png", source: url("a.jpg")), "png", "a PNG named .jpg is written as .png")
        XCTAssertEqual(CompressionPlan.outputExtension(detectedType: "public.jpeg", source: url("noextension")), "jpg")
        XCTAssertEqual(CompressionPlan.outputExtension(detectedType: "public.heic", source: url("a.heif")), "heif")
        XCTAssertEqual(CompressionPlan.outputExtension(detectedType: "org.webmproject.webp", source: url("a.png")), "webp")
    }
}
