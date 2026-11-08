import Foundation
import CZlib

/// The system zlib, as little as the PNG optimizer needs: deflate with a chosen level and strategy, inflate with a size
/// cap, and CRC-32. Pure functions on byte arrays.
enum Zlib {
    /// zlib strategies worth trying on PNG data.
    enum Strategy: Int32 {
        case standard = 0   // Z_DEFAULT_STRATEGY
        case filtered = 1   // Z_FILTERED: for data that went through PNG filters
    }

    /// A zlib stream (header, deflate data, Adler-32) of `input`; `nil` if zlib fails.
    static func deflate(_ input: [UInt8], level: Int32, strategy: Strategy = .standard) -> [UInt8]? {
        var stream = z_stream()
        guard deflateInit2_(&stream, level, Z_DEFLATED, 15, 9, strategy.rawValue, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))) + 16)
        var input = input
        let status: Int32 = input.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = uInt(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = uInt(outBuffer.count)
                return CZlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { return nil }
        return Array(output.prefix(Int(stream.total_out)))
    }

    /// The data inside a zlib stream; `nil` for a corrupt or truncated stream, or one that would inflate past `limit` bytes.
    static func inflate(_ input: [UInt8], limit: Int) -> [UInt8]? {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        var input = input
        var failed = false
        input.withUnsafeMutableBufferPointer { inBuffer in
            stream.next_in = inBuffer.baseAddress
            stream.avail_in = uInt(inBuffer.count)
            while true {
                var produced = 0
                let status: Int32 = chunk.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(outBuffer.count)
                    let status = CZlib.inflate(&stream, Z_NO_FLUSH)
                    produced = outBuffer.count - Int(stream.avail_out)
                    return status
                }
                output.append(contentsOf: chunk.prefix(produced))
                if output.count > limit { failed = true; return }
                if status == Z_STREAM_END { return }
                if status != Z_OK && status != Z_BUF_ERROR { failed = true; return }
                if status == Z_BUF_ERROR && produced == 0 { failed = true; return }   // truncated: wants more input than there is
            }
        }
        return failed ? nil : output
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(CZlib.crc32(0, $0.baseAddress, uInt($0.count))) }
    }

    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(CZlib.crc32(0, $0.baseAddress, uInt($0.count))) }
    }
}
