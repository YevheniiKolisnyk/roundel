import Foundation
import RoundelCore
import libwebp

/// The only file that talks to libwebp, and only to its *encoder* and *mux* API. libwebp's decoder is never called:
/// reading WebP is ImageIO's job (see `ImageIOSource`), which keeps libwebp's decoding code (the source of
/// CVE-2023-4863) out of the files we open. `scripts/check-webp-decoder.sh` verifies that none of it is in the app.
enum WebPLibrary {
    /// Encodes straight (non-premultiplied) RGBA pixels, 4 bytes each, rows packed.
    static func encode(rgba: [UInt8], width: Int, height: Int, settings: WebPSettings) throws -> Data {
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw ImageConversionError.encodeFailed(format: "WebP") }
        config.lossless = settings.lossless ? 1 : 0
        config.quality = settings.quality
        config.method = Int32(settings.method)
        guard WebPValidateConfig(&config) != 0 else { throw ImageConversionError.encodeFailed(format: "WebP") }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw ImageConversionError.encodeFailed(format: "WebP") }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(width)
        picture.height = Int32(height)
        picture.use_argb = settings.lossless ? 1 : 0

        let imported = rgba.withUnsafeBufferPointer { buffer in
            WebPPictureImportRGBA(&picture, buffer.baseAddress, Int32(width * 4))
        }
        guard imported != 0 else { throw ImageConversionError.encodeFailed(format: "WebP") }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        let encoded = withUnsafeMutablePointer(to: &writer) { pointer -> Int32 in
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, let bytes = writer.mem else { throw ImageConversionError.encodeFailed(format: "WebP") }
        return Data(bytes: bytes, count: writer.size)
    }

    /// Adds the ICC profile and EXIF data to an encoded WebP as chunks of its container. Without either, the bitstream
    /// is already a complete file and is returned as it is.
    static func assemble(bitstream: Data, icc: Data?, exif: Data?) throws -> Data {
        guard icc != nil || exif != nil else { return bitstream }

        let mux: OpaquePointer? = bitstream.withUnsafeBytes { raw -> OpaquePointer? in
            var data = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
            return WebPMuxCreate(&data, 1)   // 1 = copy the data, so it does not depend on `bitstream` staying put
        }
        guard let mux else { throw ImageConversionError.encodeFailed(format: "WebP") }
        defer { WebPMuxDelete(mux) }

        for (code, payload) in [("ICCP", icc), ("EXIF", exif)] {
            guard let payload else { continue }
            let status = payload.withUnsafeBytes { raw -> WebPMuxError in
                var chunk = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
                return WebPMuxSetChunk(mux, code, &chunk, 1)
            }
            guard status == WEBP_MUX_OK else { throw ImageConversionError.encodeFailed(format: "WebP") }
        }

        var assembled = WebPData()
        guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK, let bytes = assembled.bytes else {
            throw ImageConversionError.encodeFailed(format: "WebP")
        }
        defer { WebPDataClear(&assembled) }
        return Data(bytes: bytes, count: assembled.size)
    }
}
