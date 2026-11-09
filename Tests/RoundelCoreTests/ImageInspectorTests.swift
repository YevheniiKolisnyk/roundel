import XCTest
import ImageIO
import CoreGraphics
@testable import RoundelCore

/// The diagnostic that shows what a file holds and what the compress code makes of it (read-only), the MPF reader behind it,
/// the precise "extras" detection, and `dropHDRData`.
final class ImageInspectorTests: TempDirTestCase {
    // MARK: Generated files

    /// A JPEG with a disparity (depth) image attached.
    private func depthJPEG(_ name: String = "depth.jpg") throws -> URL {
        let out = NSMutableData()
        let sink = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(sink, TestImages.photo(width: 320, height: 240, grain: 3), [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        var half = [Float16](repeating: 0.5, count: 64)
        CGImageDestinationAddAuxiliaryDataInfo(sink, kCGImageAuxiliaryDataTypeDisparity, [kCGImageAuxiliaryDataInfoData: Data(bytes: &half, count: 128),
            kCGImageAuxiliaryDataInfoDataDescription: [kCGImagePropertyWidth: 8, kCGImagePropertyHeight: 8, kCGImagePropertyBytesPerRow: 16, kCGImagePropertyPixelFormat: 0x68646973 as UInt32]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(sink))
        let url = dir.appendingPathComponent(name)
        try (out as Data).write(to: url)
        return url
    }

    private func plainJPEG(_ name: String = "plain.jpg") throws -> URL {
        try TestImages.write(TestImages.photo(width: 320, height: 240, grain: 3), as: "public.jpeg", to: dir.appendingPathComponent(name), quality: 0.95)
    }

    /// An MPF APP2 segment listing `entries` (attribute, size, offset), as a camera writes it, little-endian.
    static func mpfSegment(_ entries: [(attributes: UInt32, size: UInt32, offset: UInt32)]) -> [UInt8] {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
        func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
        // TIFF header, then the MP Index IFD at offset 8 with three entries, then the MP entries.
        let ifdSize = 2 + 3 * 12 + 4
        let entriesOffset = UInt32(8 + ifdSize)
        var tiff: [UInt8] = [0x49, 0x49, 42, 0] + le32(8)
        tiff += le16(3)
        tiff += le16(0xB000) + le16(7) + le32(4) + Array("0100".utf8)                                     // version
        tiff += le16(0xB001) + le16(4) + le32(1) + le32(UInt32(entries.count))                              // number of images
        tiff += le16(0xB002) + le16(7) + le32(UInt32(16 * entries.count)) + le32(entriesOffset)             // the entries
        tiff += le32(0)
        for e in entries { tiff += le32(e.attributes) + le32(e.size) + le32(e.offset) + le16(0) + le16(0) }
        let payload = Array("MPF\0".utf8) + tiff
        let length = payload.count + 2
        return [0xFF, 0xE2, UInt8(length >> 8), UInt8(length & 255)] + payload
    }

    /// `jpeg` with `segment` inserted right after the start-of-image marker.
    private func inserting(_ segment: [UInt8], into jpeg: Data) -> Data {
        Data([0xFF, 0xD8] + segment + [UInt8](jpeg.dropFirst(2)))
    }

    // MARK: MPF

    func testTheMPFIndexOfACameraFileIsReadEntryByEntry() throws {
        let segment = Self.mpfSegment([(0x030000, 2_000_000, 0), (0x010001, 15_000, 2_000_000), (0x020002, 300_000, 2_015_000), (0x000000, 90_000, 2_315_000)])
        let entries = MPFParser.entries(in: inserting(segment, into: try Data(contentsOf: try plainJPEG())))
        XCTAssertEqual(entries.map(\.size), [2_000_000, 15_000, 300_000, 90_000])
        XCTAssertEqual(entries.map(\.role), ["primary image", "large thumbnail (VGA)", "disparity map", "undefined (0x000000)"])
        XCTAssertEqual(entries[1].offset, 2_000_000)
    }

    func testNoMPFOrABrokenOneGivesNothing() throws {
        XCTAssertEqual(MPFParser.entries(in: try Data(contentsOf: try plainJPEG())), [])
        XCTAssertEqual(MPFParser.entries(in: Data()), [])
        XCTAssertEqual(MPFParser.entries(in: Data("not a jpeg".utf8)), [])
        var cut = Self.mpfSegment([(0x030000, 10, 0)])
        cut.removeLast(20)   // the segment ends inside its entries
        XCTAssertEqual(MPFParser.entries(in: Data([0xFF, 0xD8] + cut)), [])
    }

    // MARK: Precision: what counts as "extra data"

    func testAPlainMPFPreviewDoesNotCountAsExtraDataNorSkipTheFile() async throws {
        let url = dir.appendingPathComponent("mpf.jpg")
        let segment = Self.mpfSegment([(0x030000, 20_000, 0), (0x010001, 4_000, 20_000)])   // a primary and a thumbnail: nothing else
        try inserting(segment, into: try Data(contentsOf: try plainJPEG())).write(to: url)
        let inspection = ImageInspector.inspect(url)
        XCTAssertEqual(inspection.mpfEntries.count, 2, "the MPF is seen and listed")
        XCTAssertEqual(inspection.treatedAsExtraData, [], "but it is not extra data")
        let results = await ImageCompressor(encoder: ImageIOEncoder()).compress(files: [url], options: CompressionOptions(), progress: { _, _ in })
        if case .skipped? = results.first { XCTFail("skipped: \(results)") }
    }

    func testADepthMapIsExtraDataAndNamedExactly() throws {
        let inspection = ImageInspector.inspect(try depthJPEG())
        XCTAssertEqual(inspection.treatedAsExtraData, [.disparity])
        XCTAssertTrue(inspection.auxiliaryTypesFound.contains { $0.contains("Disparity") }, "\(inspection.auxiliaryTypesFound)")
    }

    // MARK: The report

    func testTheReportForAPlainJPEGSaysNothingIsTreatedAsExtraAndWhatWouldHappen() throws {
        let text = ImageInspector.inspect(try plainJPEG()).text
        for needle in ["public.jpeg", "Images in the file: 1", "Auxiliary data", "none found", "Apple MakerNote", "MPF: none", "Treated as HDR/depth/Live Photo data: nothing",
                       "Compress (Balanced, defaults) would: re-encode"] {
            XCTAssertTrue(text.contains(needle), "\(needle)\n\(text)")
        }
    }

    func testTheReportForADepthJPEGNamesWhatTriggersTheSkipAndHowToGetPastIt() throws {
        let inspection = ImageInspector.inspect(try depthJPEG())
        let text = inspection.text
        XCTAssertTrue(text.contains("Treated as HDR/depth/Live Photo data: depth map (disparity)") || text.contains("Treated as HDR/depth/Live Photo data: disparity data"), text)
        XCTAssertTrue(text.contains("Compress (Balanced, defaults) would: SKIP"), text)
        XCTAssertTrue(text.contains("set dropHDRData to compress anyway"), text)
        XCTAssertTrue(text.contains("With dropHDRData: true it would: re-encode"), text)
        XCTAssertEqual(inspection.decision, .skip(.hasAuxiliaryData([.disparity])))
    }

    func testTheReportListsMPFEntriesAndSaysTheyAreNotTheReason() throws {
        let url = dir.appendingPathComponent("mpf.jpg")
        try inserting(Self.mpfSegment([(0x030000, 20_000, 0), (0x010001, 4_000, 20_000)]), into: try Data(contentsOf: try plainJPEG())).write(to: url)
        let text = ImageInspector.inspect(url).text
        XCTAssertTrue(text.contains("MPF: 2 entries"), text)
        XCTAssertTrue(text.contains("large thumbnail (VGA)"), text)
        XCTAssertTrue(text.contains("not a reason to skip"), text)
    }

    func testTheInspectorOnlyReadsTheFile() throws {
        let url = try depthJPEG()
        let before = try Data(contentsOf: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        _ = ImageInspector.inspect(url)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(listing(), ["depth.jpg"], "nothing created next to it")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, attributes[.modificationDate] as? Date)
    }

    func testAMissingOrNonImageFileGetsAPlainReport() throws {
        XCTAssertTrue(ImageInspector.inspect(dir.appendingPathComponent("gone.jpg")).text.contains("not found"))
        let text = dir.appendingPathComponent("t.jpg")
        try Data("hello".utf8).write(to: text)
        XCTAssertTrue(ImageInspector.inspect(text).text.contains("not an image"))
    }

    // MARK: dropHDRData end to end

    func testWithoutTheFlagADepthJPEGIsSkippedWithAMessageThatNamesTheFlag() async throws {
        let url = try depthJPEG()
        let results = await ImageCompressor(encoder: ImageIOEncoder()).compress(files: [url], options: CompressionOptions(), progress: { _, _ in })
        XCTAssertEqual(results, [.skipped(source: url, reason: .hasAuxiliaryData([.disparity]))])
        let message = CompressionSummary(results: results).message
        XCTAssertTrue(message.contains("set dropHDRData to compress anyway"), message)
        XCTAssertEqual(listing(), ["depth.jpg"])
    }

    func testWithTheFlagItIsCompressedAndTheExtrasAreGone() async throws {
        let url = try depthJPEG()
        let results = await ImageCompressor(encoder: ImageIOEncoder()).compress(files: [url], options: CompressionOptions(preset: .strong, dropHDRData: true), progress: { _, _ in })
        guard case .compressed(_, let output, let before, let after, _)? = results.first else { return XCTFail("\(results)") }
        XCTAssertLessThan(after, before)
        let inspection = ImageInspector.inspect(output)
        XCTAssertEqual(inspection.treatedAsExtraData, [], "the depth map did not survive, as promised")
        XCTAssertEqual(try TestImages.load(output).width, 320)
    }
}
