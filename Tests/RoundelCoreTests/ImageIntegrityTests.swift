import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import RoundelCore

/// ImageIO decodes a truncated PNG or JPEG as a complete image (the missing part comes out grey) and reports status
/// "complete", so damaged files need a check of their own. Generated data in memory only.
final class ImageIntegrityTests: XCTestCase {
    private func noisyImage(side: Int = 120) throws -> CGImage {
        var state: UInt32 = 42
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<bytes.count {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes[i] = i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 24)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func encoded(_ type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = try XCTUnwrap(CFDataCreateMutable(nil, 0))
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sink, try noisyImage(), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        return data as Data
    }

    // MARK: PNG

    func testACompletePngIsComplete() throws {
        XCTAssertEqual(ImageIntegrity.isComplete(try encoded(.png), detectedType: "public.png"), true)
    }

    func testATruncatedPngIsNot() throws {
        let png = try encoded(.png)
        for fraction in [0.9, 0.7, 0.3, 0.05] {
            XCTAssertEqual(ImageIntegrity.isComplete(png.prefix(Int(Double(png.count) * fraction)), detectedType: "public.png"), false, "\(fraction)")
        }
    }

    func testAPngMissingOnlyItsEndChunkIsNot() throws {
        let png = try encoded(.png)
        XCTAssertEqual(ImageIntegrity.isComplete(png.dropLast(12), detectedType: "public.png"), false, "IEND is the last 12 bytes")
    }

    func testTrailingBytesAfterThePngEndAreFine() throws {
        XCTAssertEqual(ImageIntegrity.isComplete(try encoded(.png) + Data(repeating: 0, count: 100), detectedType: "public.png"), true)
    }

    // MARK: JPEG

    func testACompleteJpegIsComplete() throws {
        XCTAssertEqual(ImageIntegrity.isComplete(try encoded(.jpeg), detectedType: "public.jpeg"), true)
    }

    func testATruncatedJpegIsNot() throws {
        let jpeg = try encoded(.jpeg)
        for fraction in [0.9, 0.7, 0.3, 0.05] {
            XCTAssertEqual(ImageIntegrity.isComplete(jpeg.prefix(Int(Double(jpeg.count) * fraction)), detectedType: "public.jpeg"), false, "\(fraction)")
        }
    }

    func testAJpegMissingOnlyItsEndMarkerIsNot() throws {
        let jpeg = try encoded(.jpeg)
        XCTAssertEqual(Array(jpeg.suffix(2)), [0xFF, 0xD9], "precondition")
        XCTAssertEqual(ImageIntegrity.isComplete(jpeg.dropLast(2), detectedType: "public.jpeg"), false)
    }

    func testTrailingBytesAfterTheJpegEndAreFine() throws {
        XCTAssertEqual(ImageIntegrity.isComplete(try encoded(.jpeg) + Data([0, 0, 0, 0]), detectedType: "public.jpeg"), true)
    }

    func testAJpegWithExifAndAThumbnailLikeEndMarkerEarlyIsStillJudgedByItsOwnEnd() throws {
        // A camera JPEG carries a whole small JPEG (with its own end marker) in the EXIF block. A truncated file must not
        // be taken for complete just because that inner end marker is present.
        let jpeg = try encoded(.jpeg, properties: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "x"]])
        XCTAssertEqual(ImageIntegrity.isComplete(jpeg, detectedType: "public.jpeg"), true)
        XCTAssertEqual(ImageIntegrity.isComplete(jpeg.prefix(jpeg.count * 6 / 10), detectedType: "public.jpeg"), false)
    }

    func testAProgressiveJpegIsJudgedCorrectly() throws {
        let progressive = try encoded(.jpeg, properties: [kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true]])
        XCTAssertEqual(ImageIntegrity.isComplete(progressive, detectedType: "public.jpeg"), true)
        XCTAssertEqual(ImageIntegrity.isComplete(progressive.prefix(progressive.count / 2), detectedType: "public.jpeg"), false)
    }

    // MARK: Other

    func testTypesWithoutACheckGetNoOpinion() throws {
        XCTAssertNil(ImageIntegrity.isComplete(try encoded(.tiff), detectedType: "public.tiff"), "ImageIO already refuses damaged TIFF and GIF")
        XCTAssertNil(ImageIntegrity.isComplete(Data([1, 2, 3]), detectedType: "org.webmproject.webp"))
    }

    func testGarbageOrEmptyDataIsNotComplete() {
        XCTAssertEqual(ImageIntegrity.isComplete(Data(), detectedType: "public.png"), false)
        XCTAssertEqual(ImageIntegrity.isComplete(Data([1, 2, 3, 4]), detectedType: "public.jpeg"), false)
    }
}
