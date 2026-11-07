import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import RoundelCore

/// The ImageIO helpers other backends build on: decoding the primary frame, the raw EXIF blob, the ICC profile and the
/// list of metadata a format without room for it would lose. Generated images in a temporary directory only.
final class ImageIOSourceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("roundel-source-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeImage(width: Int = 32, height: Int = 24, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    @discardableResult
    private func write(_ image: CGImage, as type: UTType, named name: String, properties: [CFString: Any] = [:]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    // MARK: Loading

    func testLoadingGivesThePrimaryFrameAndItsType() throws {
        let url = try write(try makeImage(width: 40, height: 20), as: .png, named: "a.png")
        let source = try ImageIOSource.load(url, upright: false)
        XCTAssertEqual(source.detectedType, "public.png")
        XCTAssertEqual(source.image.width, 40)
        XCTAssertFalse(source.isAnimated)
    }

    func testUprightLoadingAppliesTheOrientationAndClearsTheTag() throws {
        let url = try write(try makeImage(width: 40, height: 20), as: .jpeg, named: "r.jpg", properties: [kCGImagePropertyOrientation: 6])
        let raw = try ImageIOSource.load(url, upright: false)
        XCTAssertEqual(raw.image.width, 40)
        XCTAssertEqual(raw.properties[kCGImagePropertyOrientation] as? Int, 6)

        let upright = try ImageIOSource.load(url, upright: true)
        XCTAssertEqual(upright.image.width, 20)
        XCTAssertEqual(upright.image.height, 40)
        XCTAssertEqual(upright.properties[kCGImagePropertyOrientation] as? Int, 1)
    }

    func testAnAnimatedGifIsRecognized() throws {
        let url = dir.appendingPathComponent("anim.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for _ in 0..<2 { CGImageDestinationAddImage(destination, try makeImage(), nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertTrue(try ImageIOSource.load(url, upright: false).isAnimated)
    }

    func testANonImageCannotBeLoaded() throws {
        let url = dir.appendingPathComponent("t.png")
        try Data("nope".utf8).write(to: url)
        XCTAssertThrowsError(try ImageIOSource.load(url, upright: false)) { XCTAssertEqual($0 as? ImageConversionError, .unreadable) }
    }

    // MARK: EXIF blob

    func testTheExifBlobIsATiffStructureCarryingTheValues() throws {
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RoundelCam", kCGImagePropertyTIFFModel: "T1"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Lens 50mm"],
        ]
        let blob = try XCTUnwrap(ImageIOSource.exifBlob(from: properties))
        XCTAssertTrue(blob.prefix(4) == Data([0x49, 0x49, 0x2A, 0x00]) || blob.prefix(4) == Data([0x4D, 0x4D, 0x00, 0x2A]), "a TIFF header, without the 'Exif\\0\\0' prefix")
        XCTAssertNotNil(blob.range(of: Data("RoundelCam".utf8)))
        XCTAssertNotNil(blob.range(of: Data("Lens 50mm".utf8)))
    }

    func testTheExifBlobCarriesGpsToo() throws {
        let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 50.45, kCGImagePropertyGPSLatitudeRef: "N",
                                                                           kCGImagePropertyGPSLongitude: 30.52, kCGImagePropertyGPSLongitudeRef: "E"]]
        XCTAssertNotNil(ImageIOSource.exifBlob(from: properties))
    }

    func testTheExifBlobNeverClaimsARotationThePixelsAlreadyHave() throws {
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RoundelCam", kCGImagePropertyTIFFOrientation: 6],
        ]
        let blob = try XCTUnwrap(ImageIOSource.exifBlob(from: properties))
        // Parse the blob back with ImageIO by wrapping it in a JPEG: the orientation must be 1 or absent.
        let jpeg = try jpegCarrying(exif: blob)
        let reread = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil)).copyProperties()
        XCTAssertTrue((reread[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1)
    }

    func testFieldsImageIOInventsForEveryImageAreNotMetadata() {
        // ImageIO reports these for any image it reads; carrying them would put an empty EXIF block in every file.
        let invented: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifColorSpace: 1, kCGImagePropertyExifPixelXDimension: 8, kCGImagePropertyExifPixelYDimension: 8],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1, kCGImagePropertyTIFFOrientation: 1, kCGImagePropertyTIFFPhotometricInterpretation: 2,
                                             kCGImagePropertyTIFFResolutionUnit: 2, kCGImagePropertyTIFFXResolution: 72, kCGImagePropertyTIFFYResolution: 72],
        ]
        XCTAssertNil(ImageIOSource.exifBlob(from: invented))
    }

    func testRealMetadataNextToTheInventedFieldsIsCarried() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifColorSpace: 1, kCGImagePropertyExifPixelXDimension: 8],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RoundelCam"],
        ]
        XCTAssertNotNil(ImageIOSource.exifBlob(from: properties))
    }

    func testThePixelSizeInTheBlobIsTheRealOneNotTheHelperImagesTwoByTwo() throws {
        let properties: [CFString: Any] = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RoundelCam"]]
        let plain = try XCTUnwrap(ImageIOSource.exifBlob(from: properties))
        let plainExif = try XCTUnwrap(CGImageSourceCreateWithData(try jpegCarrying(exif: plain) as CFData, nil)).copyProperties()[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertEqual(plainExif?[kCGImagePropertyExifPixelXDimension as String] as? Int, 2, "precondition: that is what ImageIO writes")

        let blob = try XCTUnwrap(ImageIOSource.exifBlob(from: properties, pixelSize: (width: 4000, height: 3000)))
        let exif = try XCTUnwrap(CGImageSourceCreateWithData(try jpegCarrying(exif: blob) as CFData, nil)).copyProperties()[kCGImagePropertyExifDictionary as String] as? [String: Any]
        XCTAssertEqual(exif?[kCGImagePropertyExifPixelXDimension as String] as? Int, 4000)
        XCTAssertEqual(exif?[kCGImagePropertyExifPixelYDimension as String] as? Int, 3000)
        let tiff = try XCTUnwrap(CGImageSourceCreateWithData(try jpegCarrying(exif: blob) as CFData, nil)).copyProperties()[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake as String] as? String, "RoundelCam", "the rest is untouched")
    }

    func testPatchingWorksOnLittleEndianExifToo() throws {
        // A hand-made little-endian TIFF: IFD0 has one entry (the Exif IFD pointer); the Exif IFD has two SHORT sizes.
        var blob = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])                       // header, IFD0 at 8
        blob += Data([0x01, 0x00, 0x69, 0x87, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x1A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])   // 1 entry: ExifIFD -> 26
        blob += Data([0x02, 0x00,                                                               // Exif IFD at 26: 2 entries
                      0x02, 0xA0, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,  // PixelXDimension SHORT = 2
                      0x03, 0xA0, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,  // PixelYDimension SHORT = 2
                      0x00, 0x00, 0x00, 0x00])
        XCTAssertTrue(ImageIOSource.patchPixelSize(in: &blob, width: 1234, height: 567))
        XCTAssertEqual(Array(blob[36..<38]), [0xD2, 0x04], "width, 1234")
        XCTAssertEqual(Array(blob[48..<50]), [0x37, 0x02], "height, 567")
    }

    func testAWidthBeyondSixteenBitsTurnsTheEntryIntoALong() throws {
        var blob = Data([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08])
        blob += Data([0x00, 0x01, 0x87, 0x69, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x1A, 0x00, 0x00, 0x00, 0x00])
        blob += Data([0x00, 0x02,
                      0xA0, 0x02, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00,
                      0xA0, 0x03, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00,
                      0x00, 0x00, 0x00, 0x00])
        XCTAssertTrue(ImageIOSource.patchPixelSize(in: &blob, width: 70_000, height: 10))
        XCTAssertEqual(Array(blob[30..<32]), [0x00, 0x04], "type LONG")
        XCTAssertEqual(Array(blob[36..<40]), [0x00, 0x01, 0x11, 0x70], "70000")
        XCTAssertEqual(Array(blob[48..<50]), [0x00, 0x0A], "height stays a SHORT")
    }

    func testPatchingGarbageChangesNothingAndSaysSo() {
        var junk = Data([1, 2, 3])
        XCTAssertFalse(ImageIOSource.patchPixelSize(in: &junk, width: 1, height: 1))
        XCTAssertEqual(junk, Data([1, 2, 3]))
        var empty = Data()
        XCTAssertFalse(ImageIOSource.patchPixelSize(in: &empty, width: 1, height: 1))
    }

    func testNoMetadataMeansNoBlob() {
        XCTAssertNil(ImageIOSource.exifBlob(from: [:]))
        XCTAssertNil(ImageIOSource.exifBlob(from: [kCGImagePropertyOrientation: 6, kCGImagePropertyDPIWidth: 300]))
    }

    /// A JPEG file whose APP1 segment is exactly `exif` (with the Exif prefix), made by hand.
    private func jpegCarrying(exif: Data) throws -> Data {
        let plain = try XCTUnwrap(CFDataCreateMutable(nil, 0))
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(plain, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sink, try makeImage(width: 2, height: 2), nil)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let bytes = [UInt8](plain as Data)
        var payload = Data("Exif\0\0".utf8)
        payload.append(exif)
        let length = UInt16(payload.count + 2)
        var segment = Data([0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)])
        segment.append(payload)
        return Data(bytes.prefix(2)) + segment + Data(bytes.dropFirst(2))
    }

    // MARK: ICC

    func testSrgbHasNoProfileToCarryBecauseItIsTheDefault() throws {
        XCTAssertNil(ImageIOSource.iccProfile(of: try makeImage()))
    }

    func testAWideGamutImageHasAnIccProfile() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let profile = try XCTUnwrap(ImageIOSource.iccProfile(of: try makeImage(colorSpace: p3)))
        XCTAssertEqual(String(decoding: profile[36..<40], as: UTF8.self), "acsp", "an ICC profile carries this signature at offset 36")
    }

    // MARK: What a format without room for it would lose

    func testNothingIsLostFromAPlainImage() throws {
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: [:], image: try makeImage()), [])
    }

    func testIptcIsReported() throws {
        let properties: [CFString: Any] = [kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["roundel"]]]
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: properties, image: try makeImage()), ["IPTC"])
    }

    func testAResolutionOtherThanTheDefaultIsReported() throws {
        let image = try makeImage()
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: [kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300], image: image), ["resolution"])
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: [kCGImagePropertyDPIWidth: 72, kCGImagePropertyDPIHeight: 72], image: image), [], "72 dpi is what everyone assumes anyway")
    }

    func testMoreThanEightBitsPerChannelIsReported() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 16, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let deep = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: [:], image: deep), ["16-bit color"])
    }

    func testAColorSpaceThatIsNotRgbIsReported() throws {
        let cmyk = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceCMYK(),
                                           bitmapInfo: CGImageAlphaInfo.none.rawValue)).makeImage()
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: [:], image: try XCTUnwrap(cmyk)), ["color profile"])
    }

    func testSeveralLossesAreListedInAStableOrder() throws {
        let properties: [CFString: Any] = [kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["x"]], kCGImagePropertyDPIWidth: 300]
        XCTAssertEqual(ImageIOSource.droppedMetadata(properties: properties, image: try makeImage()), ["IPTC", "resolution"])
    }
}

private extension CGImageSource {
    func copyProperties() -> [String: Any] {
        CGImageSourceCopyPropertiesAtIndex(self, 0, nil) as? [String: Any] ?? [:]
    }
}
