import XCTest
@testable import RoundelCore

/// What is done with a file, decided from facts about it (pure).
final class CompressionPlanTests: XCTestCase {
    private func facts(_ type: String, animated: Bool = false, aux: [AuxiliaryKind] = [], ijg: Int? = nil, webpLossless: Bool? = nil) -> ImageFacts {
        ImageFacts(detectedType: type, isAnimated: animated, auxiliaryData: aux, jpegQualityIJG: ijg, webpIsLossless: webpLossless)
    }
    private func decide(_ f: ImageFacts, _ o: CompressionOptions = CompressionOptions()) -> CompressionDecision { CompressionPlan.decide(f, options: o) }
    private func options(_ preset: CompressionPreset, quality: Double? = nil, maxDimension: Int? = nil, strip: Bool? = nil, dropHDR: Bool? = nil, reduce: Bool? = nil) -> CompressionOptions {
        CompressionOptions(preset: preset, quality: quality, maxDimension: maxDimension, stripMetadata: strip, dropHDRData: dropHDR, reducePNGColors: reduce)
    }

    // MARK: Presets

    func testThePresetNumbers() {
        // Strong's numbers are the fixed fallback (and the safe ceiling of its search): the quality that still held a similarity of 0.88
        // on the most textured generated picture (JPEG 0.35, HEIC 0.25, WebP 60).
        XCTAssertEqual(CompressionPreset.allCases.map(\.jpegQuality), [0.70, 0.55, 0.35])
        XCTAssertEqual(CompressionPreset.allCases.map(\.heicQuality), [0.65, 0.55, 0.25])
        XCTAssertEqual(CompressionPreset.allCases.map(\.webpQuality), [0.80, 0.70, 0.60])
        XCTAssertEqual(CompressionPreset.allCases.map(\.title), ["Light", "Balanced", "Strong"])
        XCTAssertEqual(CompressionPreset.allCases.map(\.rawValue), ["light", "balanced", "strong"])
    }

    func testPresetsGetStrongerNotWeaker() {
        for (a, b) in zip(CompressionPreset.allCases, CompressionPreset.allCases.dropFirst()) {
            XCTAssertGreaterThan(a.jpegQuality, b.jpegQuality); XCTAssertGreaterThan(a.heicQuality, b.heicQuality); XCTAssertGreaterThan(a.webpQuality, b.webpQuality)
        }
    }

    func testOptionsFromParams() {
        XCTAssertEqual(CompressionOptions(params: Params(.object([:]))), CompressionOptions(preset: .balanced), "balanced by default, nothing decided by the user")
        let full = Params(.object(["preset": .string("strong"), "quality": .number(0.3), "maxDimension": .number(2048), "stripMetadata": .bool(true), "dropHDRData": .bool(true), "reducePNGColors": .bool(false)]))
        XCTAssertEqual(CompressionOptions(params: full), CompressionOptions(preset: .strong, quality: 0.3, maxDimension: 2048, stripMetadata: true, dropHDRData: true, reducePNGColors: false))
        XCTAssertEqual(CompressionOptions(params: Params(.object(["preset": .string("nonsense")]))).preset, .balanced)
    }

    // MARK: PNG

    func testPNGGoesToTheOptimizerWithEffortFromThePreset() {
        XCTAssertEqual(decide(facts("public.png"), options(.light)), .optimizePNG(.init(effort: .light, stripMetadata: false), reduceColors: false))
        XCTAssertEqual(decide(facts("public.png"), options(.balanced)), .optimizePNG(.init(effort: .thorough, stripMetadata: false), reduceColors: false))
        XCTAssertEqual(decide(facts("public.png"), options(.strong)), .optimizePNG(.init(effort: .thorough, stripMetadata: true), reduceColors: true), "Strong strips and may reduce colors")
        XCTAssertEqual(decide(facts("public.png"), options(.balanced, quality: 0.1, strip: true)), .optimizePNG(.init(effort: .thorough, stripMetadata: true), reduceColors: false), "a quality never makes PNG lossy")
    }

    func testAnimatedPNGIsSkipped() {
        XCTAssertEqual(decide(facts("public.png", animated: true)), .skip(.animated))
    }

    // MARK: JPEG

    // MARK: Strong searches per file

    func testStrongSearchesForTheLowestQualityThatStillLooksTheSame() {
        guard case .reencodeAdaptive(let jpeg, let o, let range) = decide(facts("public.jpeg", ijg: 96), options(.strong)) else { return XCTFail("adaptive") }
        XCTAssertEqual(jpeg.key, "jpeg"); XCTAssertEqual(range, 30...55)
        XCTAssertEqual(o.quality, 0.35, "the fixed fallback")
        XCTAssertTrue(o.stripMetadata)
        guard case .reencodeAdaptive(_, let h, let heic) = decide(facts("public.heic"), options(.strong)) else { return XCTFail() }
        XCTAssertEqual(heic, 20...55); XCTAssertEqual(h.quality, 0.25)
        guard case .reencodeAdaptive(_, let w, let webp) = decide(facts("org.webmproject.webp", webpLossless: false), options(.strong)) else { return XCTFail() }
        XCTAssertEqual(webp, 30...70); XCTAssertEqual(w.quality, 0.60)
    }

    func testTheSearchRangeOfAJPEGEndsAtWhatItsOwnQualityAllows() throws {
        guard case .reencodeAdaptive(_, _, let range) = decide(facts("public.jpeg", ijg: 80), options(.strong)) else { return XCTFail() }
        XCTAssertEqual(range.lowerBound, 30)
        let cap = try XCTUnwrap(JPEGQuality.cap(forSourceIJG: 80))
        XCTAssertEqual(range.upperBound, Int((cap * 100).rounded(.down)))
        XCTAssertLessThan(range.upperBound, 55)
        XCTAssertEqual(decide(facts("public.jpeg", ijg: 45), options(.strong)), .alreadyOptimal)
    }

    func testOnlyStrongSearchesAndAnExplicitQualityOrALosslessFileDoesNot() {
        for preset in [CompressionPreset.light, .balanced] {
            guard case .reencode = decide(facts("public.jpeg", ijg: 96), options(preset)) else { return XCTFail("\(preset) is fixed") }
        }
        guard case .reencode(_, let o) = decide(facts("public.jpeg", ijg: 96), options(.strong, quality: 0.5)) else { return XCTFail("an explicit quality is used as given") }
        XCTAssertEqual(o.quality, 0.5)
        guard case .reencode(_, let lossless) = decide(facts("org.webmproject.webp", webpLossless: true), options(.strong)) else { return XCTFail("lossless is not searched") }
        XCTAssertTrue(lossless.lossless)
    }

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
        guard case .reencodeAdaptive(_, let strong, _) = decide(facts("public.jpeg", ijg: 96), options(.strong)) else { return XCTFail("Strong searches") }
        XCTAssertEqual(strong.quality, 0.35, "its fixed fallback")
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
            let decision = decide(facts("public.heic"), options(preset))
            let pair: (ImageFormat, ImageEncodingOptions)
            switch decision {
            case .reencode(let f, let o), .reencodeAdaptive(let f, let o, _): pair = (f, o)
            default: return XCTFail("re-encode")
            }
            let (format, o) = pair
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
            XCTAssertEqual(decide(facts(type, aux: [.hdrGainMap, .depth], ijg: 95)), .skip(.hasAuxiliaryData([.hdrGainMap, .depth])), type)
            XCTAssertEqual(decide(facts(type, aux: [.livePhoto])), .skip(.hasAuxiliaryData([.livePhoto])), type)
        }
    }

    func testDropHDRDataAllowsTheReEncodeAnyway() {
        for type in ["public.heic", "public.jpeg"] {
            guard case .reencode = decide(facts(type, aux: [.hdrGainMap, .depth, .livePhoto], ijg: 95), options(.balanced, dropHDR: true)) else { return XCTFail(type) }
        }
        XCTAssertEqual(decide(facts("public.jpeg", aux: [.depth], ijg: 95), options(.balanced, dropHDR: false)), .skip(.hasAuxiliaryData([.depth])), "off by default")
    }

    // MARK: What a preset implies, and what the user's own parameters override

    func testEffectiveSettingsFollowThePresetUnlessTheUserSaidOtherwise() {
        let cases: [(CompressionPreset, Bool, Bool, Bool)] = [(.light, false, false, false), (.balanced, false, false, false), (.strong, true, true, true)]
        for (preset, strip, drop, reduce) in cases {
            let o = CompressionOptions(preset: preset)
            XCTAssertEqual([o.stripsMetadata, o.dropsHDRData, o.reducesPNGColors], [strip, drop, reduce], "\(preset)")
        }
        let overridden = CompressionOptions(preset: .strong, stripMetadata: false, dropHDRData: false, reducePNGColors: false)
        XCTAssertEqual([overridden.stripsMetadata, overridden.dropsHDRData, overridden.reducesPNGColors], [false, false, false], "explicit parameters win over what Strong implies")
        let forced = CompressionOptions(preset: .light, stripMetadata: true, dropHDRData: true, reducePNGColors: true)
        XCTAssertEqual([forced.stripsMetadata, forced.dropsHDRData, forced.reducesPNGColors], [true, true, true], "and they can add to a gentler preset")
    }

    func testStrongReEncodesFilesWithExtrasAndStripsButLightSkipsThem() {
        guard case .reencodeAdaptive(_, let strong, _) = decide(facts("public.jpeg", aux: [.hdrGainMap, .livePhoto], ijg: 95), options(.strong)) else { return XCTFail("Strong implies dropHDRData") }
        XCTAssertTrue(strong.stripMetadata)
        XCTAssertFalse(strong.carryXMP)
        XCTAssertEqual(decide(facts("public.jpeg", aux: [.hdrGainMap], ijg: 95), options(.light)), .skip(.hasAuxiliaryData([.hdrGainMap])))
        XCTAssertEqual(decide(facts("public.jpeg", aux: [.hdrGainMap], ijg: 95), options(.strong, dropHDR: false)), .skip(.hasAuxiliaryData([.hdrGainMap])), "an explicit false wins")
    }

    func testOnlyAPresetThatKeepsMetadataCarriesXMP() {
        for preset in [CompressionPreset.light, .balanced] {
            guard case .reencode(_, let o) = decide(facts("public.jpeg", ijg: 95), options(preset)) else { return XCTFail() }
            XCTAssertFalse(o.stripMetadata); XCTAssertTrue(o.carryXMP, "\(preset)")
        }
        guard case .reencode(_, let o) = decide(facts("public.heic"), options(.balanced, strip: true)) else { return XCTFail() }
        XCTAssertTrue(o.stripMetadata); XCTAssertFalse(o.carryXMP)
    }

    func testDropHDRDataChangesNothingForFilesWithoutExtras() {
        let withFlag = decide(facts("public.jpeg", ijg: 95), options(.balanced, dropHDR: true))
        XCTAssertEqual(withFlag, decide(facts("public.jpeg", ijg: 95), options(.balanced)))
        XCTAssertEqual(decide(facts("public.png", aux: [.depth]), options(.balanced)), .optimizePNG(.init(effort: .thorough, stripMetadata: false), reduceColors: false), "PNG is never skipped for extras")
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
        XCTAssertEqual(CompressionSkipReason.hasAuxiliaryData([.hdrGainMap]).message, "has an HDR gain map, skipped (set dropHDRData to compress anyway)")
        XCTAssertEqual(CompressionSkipReason.hasAuxiliaryData([.hdrGainMap, .depth]).message, "has an HDR gain map and depth data, skipped (set dropHDRData to compress anyway)")
        XCTAssertEqual(CompressionSkipReason.hasAuxiliaryData([.hdrGainMap, .portraitMatte, .livePhoto]).message, "has an HDR gain map, a portrait matte and Live Photo pairing, skipped (set dropHDRData to compress anyway)")
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
