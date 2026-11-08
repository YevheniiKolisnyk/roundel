import Foundation

/// What a WebP file holds, read from its RIFF chunk names. No pixels are decoded (libwebp's decoder is never used).
public enum WebPContainer {
    public enum Kind: Equatable, Sendable { case lossy, lossless, animated }

    /// `nil` if this is not a complete WebP container with an image in it.
    public static func kind(of data: Data) -> Kind? {
        let bytes = [UInt8](data.prefix(1 << 16))   // the chunk names are near the start; a big image chunk is only skipped over
        guard data.count >= 20, bytes.count >= 12, Array(bytes[0..<4]) == Array("RIFF".utf8), Array(bytes[8..<12]) == Array("WEBP".utf8) else { return nil }
        var found: Kind?
        var offset = 12
        var position = 12   // position in the whole file, as `offset` is within the prefix we copied
        while position + 8 <= data.count {
            guard offset + 8 <= bytes.count else { break }
            let name = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
            guard position + 8 + size <= data.count else { return nil }   // cut off
            switch name {
            case "ANIM", "ANMF": return .animated
            case "VP8L": found = found ?? .lossless
            case "VP8 ": found = found ?? .lossy
            default: break
            }
            let step = 8 + size + (size % 2)
            offset += step
            position += step
        }
        return found
    }
}
