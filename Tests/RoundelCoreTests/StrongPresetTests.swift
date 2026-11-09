import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

/// What the presets keep and remove, on real files: Light and Balanced keep EXIF, GPS, IPTC, XMP and the color profile;
/// Strong removes everything that does not change how the picture looks, but never the orientation or the profile.
final class StrongPresetTests: TempDirTestCase {
    private let compressor = ImageCompressor(encoder: ImageIOEncoder())

    /// A rich camera-like JPEG: GPS, EXIF, orientation 6, Display P3, an XMP label, and a depth map.
    private func richJPEG(_ name: String = "rich.jpg") throws -> URL {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 480, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: p3, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let base = TestImages.photo(width: 480, height: 360, grain: 3)
        context.draw(base, in: CGRect(x: 0, y: 0, width: 480, height: 360))
        let image = try XCTUnwrap(context.makeImage())

        let out = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        let xmp = CGImageMetadataCreateMutable()
        XCTAssertTrue(CGImageMetadataSetValueWithPath(xmp, nil, "xmp:Label" as CFString, "Blue" as CFString))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 50.45, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 30.52, kCGImagePropertyGPSLongitudeRef: "E"]
        let exif: [CFString: Any] = [kCGImagePropertyExifLensModel: "Test Lens"]
        CGImageDestinationAddImageAndMetadata(sink, image, xmp, [kCGImageDestinationLossyCompressionQuality: 0.95, kCGImagePropertyGPSDictionary: gps,
                                                                kCGImagePropertyExifDictionary: exif, kCGImagePropertyOrientation: 6] as CFDictionary)
        var half = [Float16](repeating: 0.5, count: 64)
        CGImageDestinationAddAuxiliaryDataInfo(sink, kCGImageAuxiliaryDataTypeDisparity, [kCGImageAuxiliaryDataInfoData: Data(bytes: &half, count: 128),
            kCGImageAuxiliaryDataInfoDataDescription: [kCGImagePropertyWidth: 8, kCGImagePropertyHeight: 8, kCGImagePropertyBytesPerRow: 16, kCGImagePropertyPixelFormat: 0x68646973 as UInt32]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let url = dir.appendingPathComponent(name)
        try (out as Data).write(to: url)
        return url
    }

    private func xmpLabel(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let md = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(md, nil, "xmp:Label" as CFString) else { return nil }
        return CGImageMetadataTagCopyValue(tag) as? String
    }

    private func compress(_ url: URL, _ options: CompressionOptions) async throws -> (output: URL, changes: CompressionChanges) {
        let results = await compressor.compress(files: [url], options: options, progress: { _, _ in })
        guard case .compressed(_, let output, _, _, let changes)? = results.first else { XCTFail("\(results)"); throw CancellationError() }
        return (output, changes)
    }

    func testTheSourceHasEverythingWeCheckFor() throws {
        let url = try richJPEG()
        let p = TestImages.properties(of: url)
        XCTAssertNotNil(p[kCGImagePropertyGPSDictionary]); XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertEqual(xmpLabel(url), "Blue")
        XCTAssertEqual(ImageInspector.inspect(url).treatedAsExtraData, [.disparity])
    }

    // MARK: Light and Balanced keep metadata

    func testLightAndBalancedKeepExifGpsXmpAndTheProfileWhenTheExtrasAreAllowedToGo() async throws {
        for preset in [CompressionPreset.light, .balanced] {
            let url = try richJPEG("rich-\(preset.rawValue).jpg")
            let (output, changes) = try await compress(url, CompressionOptions(preset: preset, dropHDRData: true))
            let p = TestImages.properties(of: output)
            XCTAssertNotNil(p[kCGImagePropertyGPSDictionary], "\(preset): GPS")
            XCTAssertEqual((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] as? String, "Test Lens", "\(preset): EXIF")
            XCTAssertEqual(xmpLabel(output), "Blue", "\(preset): XMP is carried over")
            XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int, 6)
            XCTAssertEqual(try TestImages.load(output).colorSpace?.name as String?, CGColorSpace.displayP3 as String, "\(preset): ICC")
            XCTAssertFalse(changes.metadataRemoved, "\(preset)")
            XCTAssertEqual(changes.extrasRemoved, [.disparity], "\(preset): the depth map was dropped because the user allowed it")
        }
    }

    func testLightSkipsAFileWithExtrasUnlessAllowed() async throws {
        let url = try richJPEG()
        let results = await compressor.compress(files: [url], options: CompressionOptions(preset: .light), progress: { _, _ in })
        XCTAssertEqual(results, [.skipped(source: url, reason: .hasAuxiliaryData([.disparity]))])
    }

    // MARK: Strong removes what does not change the picture

    func testStrongRemovesGpsExifXmpAndTheDepthMapButKeepsOrientationAndTheProfile() async throws {
        let url = try richJPEG()
        let (output, changes) = try await compress(url, CompressionOptions(preset: .strong))
        let p = TestImages.properties(of: output)
        XCTAssertNil(p[kCGImagePropertyGPSDictionary], "GPS")
        XCTAssertNil((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel], "EXIF")
        XCTAssertNil(xmpLabel(output), "XMP")
        XCTAssertEqual(ImageInspector.inspect(output).treatedAsExtraData, [], "the depth map")
        XCTAssertEqual(p[kCGImagePropertyOrientation] as? Int, 6, "the picture stays upright")
        XCTAssertEqual(try TestImages.load(output).colorSpace?.name as String?, CGColorSpace.displayP3 as String, "the profile")
        XCTAssertTrue(changes.metadataRemoved)
        XCTAssertEqual(changes.extrasRemoved, [.disparity])
    }

    func testStrongNeverChangesTheResolutionUnlessAskedTo() async throws {
        let url = try richJPEG()
        let (output, _) = try await compress(url, CompressionOptions(preset: .strong))
        XCTAssertEqual(try TestImages.load(output).width, 480)
        XCTAssertEqual(try TestImages.load(output).height, 360)
        let (small, _) = try await compress(url, CompressionOptions(preset: .strong, maxDimension: 240))
        // The source is stored 480 x 360 with a 90-degree orientation tag: shrunk to 240 it is 180 x 240 upright.
        XCTAssertEqual(max(try TestImages.load(small).width, try TestImages.load(small).height), 240)
    }

    func testExplicitParametersWinOverWhatStrongImplies() async throws {
        let url = try richJPEG()
        let kept = try await compress(url, CompressionOptions(preset: .strong, stripMetadata: false))
        XCTAssertNotNil(TestImages.properties(of: kept.output)[kCGImagePropertyGPSDictionary], "stripMetadata: false keeps the GPS")
        XCTAssertFalse(kept.changes.metadataRemoved)
        try FileManager.default.removeItem(at: kept.output)
        let results = await compressor.compress(files: [url], options: CompressionOptions(preset: .strong, dropHDRData: false), progress: { _, _ in })
        XCTAssertEqual(results, [.skipped(source: url, reason: .hasAuxiliaryData([.disparity]))], "dropHDRData: false makes Strong skip it")
    }

    // MARK: PNG

    func testStrongRemovesPNGTextAndTimeButKeepsColorChunksAndBalancedKeepsEverything() async throws {
        let icc = ("iCCP", Array("p\0\0".utf8) + (Zlib.deflate([1, 2, 3, 4], level: 6) ?? []))
        let spec = TestPNG.Spec(width: 60, height: 40, colorType: 2, bitDepth: 8, sample: { (x: Int, y: Int, c: Int) -> Int in (x * 4 + y * 3 + c * 50) & 255 },
                                chunks: [icc, ("gAMA", [0, 1, 0x86, 0xA0]), ("tEXt", Array("Comment\0hi".utf8)), ("tIME", [7, 233, 11, 8, 1, 2, 3])])
        let url = dir.appendingPathComponent("p.png")
        try TestPNG.make(spec).write(to: url)
        let balanced = try await compress(url, CompressionOptions(preset: .balanced, reducePNGColors: false))
        XCTAssertEqual(TestPNG.chunks(of: try Data(contentsOf: balanced.output)).map(\.type), ["IHDR", "iCCP", "gAMA", "tEXt", "tIME", "IDAT", "IEND"])
        XCTAssertFalse(balanced.changes.metadataRemoved)
        try FileManager.default.removeItem(at: balanced.output)
        let strong = try await compress(url, CompressionOptions(preset: .strong, reducePNGColors: false))
        XCTAssertEqual(TestPNG.chunks(of: try Data(contentsOf: strong.output)).map(\.type), ["IHDR", "iCCP", "gAMA", "IDAT", "IEND"])
        XCTAssertTrue(strong.changes.metadataRemoved)
    }
}
