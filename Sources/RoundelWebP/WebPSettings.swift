import Foundation
import RoundelCore

/// How the user's options become libwebp's settings. Pure.
struct WebPSettings: Equatable {
    /// WebP cannot hold an image with a side beyond this many pixels.
    static let maxDimension = 16383

    var lossless: Bool
    /// 0-100. For lossy output the image quality; for lossless output libwebp reads it as compression effort
    /// (0 = quick and bigger, 100 = slow and smaller), so the same `quality` option keeps its "higher is better" feel.
    var quality: Float
    /// 0-6, speed/size trade-off of the encoder; 4 is libwebp's default.
    var method: Int

    static func make(from options: ImageEncodingOptions) -> WebPSettings {
        let fallback = options.lossless ? 0.75 : 0.8
        let requested = options.quality.flatMap { $0.isFinite ? $0 : nil } ?? fallback
        return WebPSettings(lossless: options.lossless, quality: Float(min(max(requested, 0), 1) * 100), method: 4)
    }
}
