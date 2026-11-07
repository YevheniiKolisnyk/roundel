import XCTest
@testable import RoundelCore

final class ImageFormatTests: XCTestCase {
    private let everything = ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp",
                              "public.avif", "com.adobe.pdf", "com.microsoft.ico", "public.jpeg-2000"]

    func testTheCatalogIsInTheAgreedOrder() {
        XCTAssertEqual(ImageFormats.catalog.map(\.key), ["png", "jpeg", "heic", "tiff", "gif", "bmp", "avif"])
        XCTAssertEqual(ImageFormats.catalog.map(\.displayName), ["PNG", "JPEG", "HEIC", "TIFF", "GIF", "BMP", "AVIF"])
    }

    func testOnlyJpegHeicAndAvifAreLossy() {
        XCTAssertEqual(ImageFormats.catalog.filter(\.isLossy).map(\.key), ["jpeg", "heic", "avif"])
    }

    func testOnlyJpegCannotStoreAlpha() {
        XCTAssertEqual(ImageFormats.catalog.filter { !$0.supportsAlpha }.map(\.key), ["jpeg"])
    }

    func testFileExtensionsAreTheUsualOnes() {
        let byKey = Dictionary(uniqueKeysWithValues: ImageFormats.catalog.map { ($0.key, $0.fileExtension) })
        XCTAssertEqual(byKey, ["png": "png", "jpeg": "jpg", "heic": "heic", "tiff": "tiff", "gif": "gif", "bmp": "bmp", "avif": "avif"])
    }

    // MARK: Capabilities

    func testAvailableFormatsAreTheCatalogOnesTheSystemCanWrite() {
        XCTAssertEqual(ImageFormats.available(writable: everything).map(\.key), ["png", "jpeg", "heic", "tiff", "gif", "bmp", "avif"])
        XCTAssertEqual(ImageFormats.available(writable: ["public.png", "public.jpeg"]).map(\.key), ["png", "jpeg"])
    }

    func testAvifAppearsOnlyWhenTheSystemReportsIt() {
        let without = everything.filter { $0 != "public.avif" }
        XCTAssertFalse(ImageFormats.available(writable: without).contains { $0.key == "avif" })
        XCTAssertTrue(ImageFormats.available(writable: everything).contains { $0.key == "avif" })
    }

    func testTypesOutsideTheCatalogAreNeverOffered() {
        let keys = ImageFormats.available(writable: everything).map(\.typeIdentifier)
        XCTAssertFalse(keys.contains("com.adobe.pdf"))
        XCTAssertFalse(keys.contains("com.microsoft.ico"))
        XCTAssertFalse(keys.contains("public.jpeg-2000"))
    }

    func testNothingWritableMeansNothingOffered() {
        XCTAssertEqual(ImageFormats.available(writable: []), [])
    }

    func testLookupByKey() {
        XCTAssertEqual(ImageFormats.format(forKey: "jpeg")?.typeIdentifier, "public.jpeg")
        XCTAssertNil(ImageFormats.format(forKey: "webp"))
    }

    // MARK: Same-format detection (by content type, not extension)

    func testASourceInTheTargetFormatIsRecognized() {
        let jpeg = ImageFormats.format(forKey: "jpeg")!
        XCTAssertTrue(ImageFormats.isSame(detectedType: "public.jpeg", as: jpeg))
        let png = ImageFormats.format(forKey: "png")!
        XCTAssertTrue(ImageFormats.isSame(detectedType: "public.png", as: png))
    }

    func testDifferentFormatsAreNotTheSame() {
        let jpeg = ImageFormats.format(forKey: "jpeg")!
        XCTAssertFalse(ImageFormats.isSame(detectedType: "public.png", as: jpeg))
        XCTAssertFalse(ImageFormats.isSame(detectedType: "public.jpeg-2000", as: jpeg), "JPEG 2000 is another format")
        XCTAssertFalse(ImageFormats.isSame(detectedType: "public.tiff", as: jpeg))
    }

    func testEveryCatalogFormatRecognizesItself() {
        for format in ImageFormats.catalog {
            XCTAssertTrue(ImageFormats.isSame(detectedType: format.typeIdentifier, as: format), format.key)
        }
    }

    func testDisplayNameOfADetectedType() {
        XCTAssertEqual(ImageFormats.name(ofDetectedType: "public.jpeg"), "JPEG")
        XCTAssertEqual(ImageFormats.name(ofDetectedType: "public.jpeg-2000"), "JPEG 2000")
        XCTAssertNotNil(ImageFormats.name(ofDetectedType: "com.compuserve.gif"))
    }
}
