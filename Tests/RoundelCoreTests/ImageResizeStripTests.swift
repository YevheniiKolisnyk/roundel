import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

/// `maxDimension` and `stripMetadata` in the ImageIO encoder (they apply the same way to every re-encode).
final class ImageResizeStripTests: TempDirTestCase {
    private let encoder = ImageIOEncoder()
    private var jpeg: ImageFormat { ImageFormats.format(forKey: "jpeg")! }
    private var png: ImageFormat { ImageFormats.format(forKey: "png")! }

    private func source(width: Int = 300, height: Int = 200, properties: [CFString: Any] = [:]) throws -> URL {
        try TestImages.write(TestImages.photo(width: width, height: height), as: "public.jpeg", to: dir.appendingPathComponent("src.jpg"), quality: 0.9, properties: properties)
    }

    func testALargePictureIsShrunkToTheLimitKeepingItsProportions() throws {
        let out = dir.appendingPathComponent("o.jpg")
        _ = try encoder.encode(source: try source(), to: out, format: jpeg, options: ImageEncodingOptions(quality: 0.7, maxDimension: 150))
        let p = TestImages.properties(of: out)
        XCTAssertEqual(p[kCGImagePropertyPixelWidth] as? Int, 150)
        XCTAssertEqual(p[kCGImagePropertyPixelHeight] as? Int, 100)
    }

    func testASmallerPictureIsNeverEnlarged() throws {
        let out = dir.appendingPathComponent("o.jpg")
        _ = try encoder.encode(source: try source(width: 100, height: 60), to: out, format: jpeg, options: ImageEncodingOptions(quality: 0.7, maxDimension: 4000))
        XCTAssertEqual(TestImages.properties(of: out)[kCGImagePropertyPixelWidth] as? Int, 100)
    }

    func testAPictureWithoutALimitKeepsItsSize() throws {
        let out = dir.appendingPathComponent("o.jpg")
        _ = try encoder.encode(source: try source(), to: out, format: jpeg, options: ImageEncodingOptions(quality: 0.7))
        XCTAssertEqual(TestImages.properties(of: out)[kCGImagePropertyPixelWidth] as? Int, 300)
    }

    func testAResizedRotatedPictureIsNotRotatedTwice() throws {
        // Stored 300 x 200 with orientation 6 (rotate 90 degrees): it shows 200 x 300. Limited to 150 it must be 100 x 150 upright.
        let src = try source(properties: [kCGImagePropertyOrientation: 6])
        let out = dir.appendingPathComponent("o.jpg")
        _ = try encoder.encode(source: src, to: out, format: jpeg, options: ImageEncodingOptions(quality: 0.7, maxDimension: 150))
        let p = TestImages.properties(of: out)
        let w = p[kCGImagePropertyPixelWidth] as? Int ?? 0, h = p[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = p[kCGImagePropertyOrientation] as? Int ?? 1
        // Either the pixels are upright (taller than wide, tag 1) or they are stored sideways with the tag: the shown shape is what matters.
        let shownWidth = orientation >= 5 ? h : w, shownHeight = orientation >= 5 ? w : h
        XCTAssertEqual(shownWidth, 100)
        XCTAssertEqual(shownHeight, 150)
    }

    func testMetadataIsKeptByDefaultAndStrippedOnRequestButOrientationAndProfileStay() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 50.45, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 30.52, kCGImagePropertyGPSLongitudeRef: "E"]
        let exif: [CFString: Any] = [kCGImagePropertyExifUserComment: "hello", kCGImagePropertyExifLensModel: "Test Lens"]
        let src = try source(properties: [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyExifDictionary: exif, kCGImagePropertyOrientation: 6])
        XCTAssertNotNil(TestImages.properties(of: src)[kCGImagePropertyGPSDictionary], "precondition")

        let kept = dir.appendingPathComponent("kept.jpg"), stripped = dir.appendingPathComponent("stripped.jpg")
        _ = try encoder.encode(source: src, to: kept, format: jpeg, options: ImageEncodingOptions(quality: 0.7))
        _ = try encoder.encode(source: src, to: stripped, format: jpeg, options: ImageEncodingOptions(quality: 0.7, stripMetadata: true))

        let k = TestImages.properties(of: kept), s = TestImages.properties(of: stripped)
        XCTAssertNotNil(k[kCGImagePropertyGPSDictionary], "GPS kept by default")
        XCTAssertEqual((k[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] as? String, "Test Lens")
        XCTAssertEqual(k[kCGImagePropertyOrientation] as? Int, 6)
        XCTAssertNil(s[kCGImagePropertyGPSDictionary], "GPS gone")
        XCTAssertNil((s[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel], "EXIF details gone")
        XCTAssertEqual(s[kCGImagePropertyOrientation] as? Int, 6, "but the picture stays upright")
    }

    func testTheColorProfileSurvivesRecompressionAndStripping() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: p3, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let src = try TestImages.write(try XCTUnwrap(context.makeImage()), as: "public.jpeg", to: dir.appendingPathComponent("p3.jpg"), quality: 0.9)
        for strip in [false, true] {
            let out = dir.appendingPathComponent("p3-\(strip).jpg")
            _ = try encoder.encode(source: src, to: out, format: jpeg, options: ImageEncodingOptions(quality: 0.6, stripMetadata: strip))
            let name = try TestImages.load(out).colorSpace?.name as String?
            XCTAssertEqual(name, CGColorSpace.displayP3 as String, "strip \(strip)")
        }
    }

    func testConvertingWithoutTheNewOptionsBehavesAsBefore() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 50.45, kCGImagePropertyGPSLatitudeRef: "N"]
        let src = try source(properties: [kCGImagePropertyGPSDictionary: gps])
        let out = dir.appendingPathComponent("o.jpg")
        _ = try encoder.encode(source: src, to: out, format: jpeg, options: ImageEncodingOptions(quality: 0.8))
        XCTAssertNotNil(TestImages.properties(of: out)[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(TestImages.properties(of: out)[kCGImagePropertyPixelWidth] as? Int, 300)
    }
}
