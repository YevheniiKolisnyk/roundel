import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import RoundelCore

final class ImageProbeTests: TempDirTestCase {
    private let probe = ImageIOProbe()

    private func facts(_ url: URL) throws -> ImageFacts {
        let type = try XCTUnwrap(ImageIOEncoder().detectType(of: url))
        return probe.facts(of: url, detectedType: type)
    }

    func testAPlainJPEGHasItsQualityAndNothingSpecial() throws {
        let url = try TestImages.write(TestImages.photo(), as: "public.jpeg", to: dir.appendingPathComponent("a.jpg"), quality: 0.8)
        let f = try facts(url)
        XCTAssertEqual(f.detectedType, "public.jpeg")
        XCTAssertFalse(f.isAnimated)
        XCTAssertFalse(f.hasAuxiliaryData)
        XCTAssertEqual(Double(try XCTUnwrap(f.jpegQualityIJG)), 94, accuracy: 3)
        XCTAssertNil(f.webpIsLossless)
    }

    func testAJPEGWithADepthMapHasAuxiliaryData() throws {
        let out = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, TestImages.photo(), nil)
        var half = [Float16](repeating: 0.5, count: 64)
        let info: [CFString: Any] = [kCGImageAuxiliaryDataInfoData: Data(bytes: &half, count: 128),
                                     kCGImageAuxiliaryDataInfoDataDescription: [kCGImagePropertyWidth: 8, kCGImagePropertyHeight: 8, kCGImagePropertyBytesPerRow: 16, kCGImagePropertyPixelFormat: 0x68646973 as UInt32]]
        CGImageDestinationAddAuxiliaryDataInfo(sink, kCGImageAuxiliaryDataTypeDisparity, info as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let url = dir.appendingPathComponent("depth.jpg")
        try (out as Data).write(to: url)
        XCTAssertTrue(try facts(url).hasAuxiliaryData)
    }

    func testALivePhotoStillIsRecognizedByItsAppleContentIdentifier() throws {
        let apple: [CFString: Any] = ["17" as CFString: "AB12CD34-0000-0000-0000-000000000000"]
        let url = try TestImages.write(TestImages.photo(), as: "public.jpeg", to: dir.appendingPathComponent("live.jpg"), properties: [kCGImagePropertyMakerAppleDictionary: apple])
        // ImageIO may or may not keep a MakerApple dictionary it was given; only assert what it keeps.
        if TestImages.properties(of: url)[kCGImagePropertyMakerAppleDictionary] != nil {
            XCTAssertTrue(try facts(url).hasAuxiliaryData)
        }
        XCTAssertTrue(ImageIOProbe.isLivePhoto(properties: [kCGImagePropertyMakerAppleDictionary: apple]))
        XCTAssertFalse(ImageIOProbe.isLivePhoto(properties: [kCGImagePropertyMakerAppleDictionary: ["1": 1]]))
        XCTAssertFalse(ImageIOProbe.isLivePhoto(properties: [:]))
    }

    func testAnAnimatedGIFIsAnimatedAndAStillPNGIsNot() throws {
        let gif = dir.appendingPathComponent("anim.gif")
        let sink = try XCTUnwrap(CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 3, nil))
        for i in 0..<3 { CGImageDestinationAddImage(sink, TestImages.photo(width: 40, height: 30, seed: UInt32(i + 1)), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        XCTAssertTrue(try facts(gif).isAnimated)

        let png = try TestImages.write(TestImages.photo(width: 40, height: 30), as: "public.png", to: dir.appendingPathComponent("s.png"))
        XCTAssertFalse(try facts(png).isAnimated)
    }

    func testPixelCountsComeFromTheHeaderWithoutDecoding() throws {
        let url = try TestImages.write(TestImages.photo(width: 120, height: 50), as: "public.png", to: dir.appendingPathComponent("p.png"))
        XCTAssertEqual(probe.pixelCount(of: url), 6000)
        XCTAssertEqual(probe.pixelCount(of: dir.appendingPathComponent("missing.png")), 0)
        try Data("hello".utf8).write(to: dir.appendingPathComponent("t.txt"))
        XCTAssertEqual(probe.pixelCount(of: dir.appendingPathComponent("t.txt")), 0)
    }
}
