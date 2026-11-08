import XCTest
@testable import RoundelCore

final class WebPContainerTests: XCTestCase {
    private func riff(_ chunks: [(String, [UInt8])]) -> Data {
        var body = Array("WEBP".utf8)
        for (type, data) in chunks {
            body += Array(type.utf8)
            let n = UInt32(data.count)
            body += [UInt8(n & 255), UInt8(n >> 8 & 255), UInt8(n >> 16 & 255), UInt8(n >> 24 & 255)]
            body += data
            if data.count % 2 == 1 { body.append(0) }
        }
        let size = UInt32(body.count)
        return Data(Array("RIFF".utf8) + [UInt8(size & 255), UInt8(size >> 8 & 255), UInt8(size >> 16 & 255), UInt8(size >> 24 & 255)] + body)
    }

    func testLossyLosslessAndAnimatedAreToldApartByTheirChunks() {
        XCTAssertEqual(WebPContainer.kind(of: riff([("VP8 ", [1, 2, 3, 4])])), .lossy)
        XCTAssertEqual(WebPContainer.kind(of: riff([("VP8L", [0x2F, 1, 2, 3, 4])])), .lossless)
        XCTAssertEqual(WebPContainer.kind(of: riff([("VP8X", [UInt8](repeating: 0, count: 10)), ("ALPH", [1]), ("VP8 ", [1, 2, 3, 4])])), .lossy, "lossy with alpha")
        XCTAssertEqual(WebPContainer.kind(of: riff([("VP8X", [UInt8](repeating: 0, count: 10)), ("VP8L", [0x2F, 1, 2, 3, 4])])), .lossless)
        XCTAssertEqual(WebPContainer.kind(of: riff([("VP8X", [UInt8](repeating: 0, count: 10)), ("ANIM", [0, 0, 0, 0, 0, 0]), ("ANMF", [0, 1, 2]), ("VP8L", [1])])), .animated)
    }

    func testNotWebPOrTruncatedGivesNothing() {
        XCTAssertNil(WebPContainer.kind(of: Data()))
        XCTAssertNil(WebPContainer.kind(of: Data("RIFF....WAVEfmt ".utf8)))
        XCTAssertNil(WebPContainer.kind(of: Data("RIFF".utf8)))
        XCTAssertNil(WebPContainer.kind(of: riff([("EXIF", [1, 2])])), "no image chunk")
        let cut = riff([("VP8L", [UInt8](repeating: 7, count: 40))]).prefix(21)
        XCTAssertNil(WebPContainer.kind(of: Data(cut)))
    }
}
