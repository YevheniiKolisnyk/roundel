import XCTest
@testable import RoundelCore

/// Which image backend writes which format, and what the combined capability list looks like.
final class ImageBackendsTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [String] = []
        var items: [String] { lock.withLock { _items } }
        func add(_ item: String) { lock.withLock { _items.append(item) } }
    }

    private struct StubBackend: ImageBackend {
        let name: String
        let writableTypeIdentifiers: [String]
        var detected: String? = nil
        var calls = Calls()

        func detectType(of url: URL) -> String? { detected }
        func encode(source: URL, to destination: URL, format: ImageFormat, options: ImageEncodingOptions) throws -> EncodeOutcome {
            calls.add("\(name):\(source.lastPathComponent)->\(destination.lastPathComponent):\(format.key):\(options.quality.map { "\($0)" } ?? "-"):\(options.lossless)")
            return EncodeOutcome(notes: [.firstFrameOnly])
        }
    }

    private let png = ImageFormats.format(forKey: "png")!
    private let webp = ImageFormats.format(forKey: "webp")!
    private let imageIOTypes = ["public.png", "public.jpeg", "public.tiff"]

    // MARK: Priority

    func testTheFirstBackendThatCanWriteAFormatIsUsed() {
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes)
        let libwebp = StubBackend(name: "libwebp", writableTypeIdentifiers: ["org.webmproject.webp"])
        let backends = ImageBackends([imageIO, libwebp])
        XCTAssertEqual(backends.backend(for: png)?.name, "ImageIO")
        XCTAssertEqual(backends.backend(for: webp)?.name, "libwebp")
    }

    func testImageIOKeepsPriorityEvenIfItLearnsToWriteAFormatTheOtherBackendAlsoWrites() {
        // E.g. a future macOS whose ImageIO can write WebP: the system encoder wins, libwebp is not used.
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes + ["org.webmproject.webp"])
        let libwebp = StubBackend(name: "libwebp", writableTypeIdentifiers: ["org.webmproject.webp"])
        XCTAssertEqual(ImageBackends([imageIO, libwebp]).backend(for: webp)?.name, "ImageIO")
    }

    func testTheOrderOfTheListIsThePriority() {
        let a = StubBackend(name: "A", writableTypeIdentifiers: ["public.png"])
        let b = StubBackend(name: "B", writableTypeIdentifiers: ["public.png"])
        XCTAssertEqual(ImageBackends([a, b]).backend(for: png)?.name, "A")
        XCTAssertEqual(ImageBackends([b, a]).backend(for: png)?.name, "B")
    }

    func testAFormatNobodyCanWriteHasNoBackend() {
        let backends = ImageBackends([StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes)])
        XCTAssertNil(backends.backend(for: webp))
    }

    // MARK: Capabilities

    func testCapabilitiesAreTheUnionInPriorityOrderWithoutDuplicates() {
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: ["public.png", "public.jpeg"])
        let libwebp = StubBackend(name: "libwebp", writableTypeIdentifiers: ["public.png", "org.webmproject.webp"])
        XCTAssertEqual(ImageBackends([imageIO, libwebp]).writableTypeIdentifiers, ["public.png", "public.jpeg", "org.webmproject.webp"])
    }

    func testWebpAppearsInTheOfferedFormatsOnlyThroughTheMergedList() {
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes)
        let libwebp = StubBackend(name: "libwebp", writableTypeIdentifiers: ["org.webmproject.webp"])
        XCTAssertFalse(ImageFormats.available(writable: ImageBackends([imageIO]).writableTypeIdentifiers).contains { $0.key == "webp" })
        XCTAssertEqual(ImageFormats.available(writable: ImageBackends([imageIO, libwebp]).writableTypeIdentifiers).map(\.key), ["png", "jpeg", "tiff", "webp"])
    }

    func testNoBackendsMeansNoCapabilities() {
        XCTAssertEqual(ImageBackends([]).writableTypeIdentifiers, [])
    }

    func testTheMergedListFeedsTheGeneratedGroup() {
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes)
        let libwebp = StubBackend(name: "libwebp", writableTypeIdentifiers: ["org.webmproject.webp"])
        let generator = ImageConvertFormatsGenerator(capabilities: ImageBackends([imageIO, libwebp]))
        let group = GroupNode(id: "c", title: "C", children: [], generate: "image.convert.formats")
        XCTAssertEqual(generator.children(for: group).map(\.id), ["c.png", "c.jpeg", "c.tiff", "c.webp"])
    }

    // MARK: Encoding and detection

    func testEncodingGoesToTheChosenBackendWithEverythingItWasGiven() throws {
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes)
        let libwebp = StubBackend(name: "libwebp", writableTypeIdentifiers: ["org.webmproject.webp"])
        let outcome = try ImageBackends([imageIO, libwebp]).encode(
            source: URL(fileURLWithPath: "/tmp/a.png"), to: URL(fileURLWithPath: "/tmp/a.webp"),
            format: webp, options: ImageEncodingOptions(quality: 0.5, lossless: true)
        )
        XCTAssertEqual(libwebp.calls.items, ["libwebp:a.png->a.webp:webp:0.5:true"])
        XCTAssertTrue(imageIO.calls.items.isEmpty)
        XCTAssertEqual(outcome.notes, [.firstFrameOnly])
    }

    func testEncodingAFormatNoBackendCanWriteFailsInsteadOfWritingNothing() {
        let backends = ImageBackends([StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes)])
        XCTAssertThrowsError(try backends.encode(source: URL(fileURLWithPath: "/tmp/a.png"), to: URL(fileURLWithPath: "/tmp/a.webp"), format: webp, options: ImageEncodingOptions())) { error in
            XCTAssertEqual(error as? ImageConversionError, .encodeFailed(format: "WebP"))
        }
    }

    func testDetectionAsksTheBackendsInOrderAndTakesTheFirstAnswer() {
        let none = StubBackend(name: "libwebp", writableTypeIdentifiers: ["org.webmproject.webp"], detected: nil)
        let imageIO = StubBackend(name: "ImageIO", writableTypeIdentifiers: imageIOTypes, detected: "org.webmproject.webp")
        let url = URL(fileURLWithPath: "/tmp/x")
        XCTAssertEqual(ImageBackends([none, imageIO]).detectType(of: url), "org.webmproject.webp")
        XCTAssertNil(ImageBackends([none]).detectType(of: url))
        XCTAssertNil(ImageBackends([]).detectType(of: url))
    }

    func testImageIOEncoderReportsTheCapabilitiesItWasGiven() {
        struct Caps: ImageCapabilities { let writableTypeIdentifiers: [String] }
        let encoder = ImageIOEncoder(capabilities: Caps(writableTypeIdentifiers: ["public.png"]))
        XCTAssertEqual(encoder.writableTypeIdentifiers, ["public.png"])
        XCTAssertEqual(encoder.name, "ImageIO")
        XCTAssertEqual(ImageIOEncoder().writableTypeIdentifiers, SystemImageCapabilities().writableTypeIdentifiers)
    }

    func testOptionsDefaultToNoQualityAndLossy() {
        XCTAssertEqual(ImageEncodingOptions(), ImageEncodingOptions(quality: nil, lossless: false))
    }
}
