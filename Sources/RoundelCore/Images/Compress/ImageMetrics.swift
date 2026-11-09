import Foundation
import CoreGraphics

/// Pixels as 8-bit RGBA in sRGB, whatever the image's own format.
public enum ImagePixels {
    public static func rgba8(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &out, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return out }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return out
    }
}

/// How alike two pictures of the same size look: structural similarity (SSIM, 8x8 windows every 4 pixels) of the luminance and
/// of each color channel. Computed with summed-area tables, so a megapixel takes milliseconds.
public enum ImageMetrics {
    /// `min(luma SSIM, mean of the R, G and B SSIMs)`: 1 is identical. The luma alone does not see color shifts; the mean alone
    /// can hide a loss of structure. 0 if the buffers do not match the size.
    public static func similarity(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> Double {
        if width <= 0 || height <= 0 { return 1 }
        guard a.count == width * height * 4, b.count == a.count else { return 0 }
        let luma = lumaSSIM(a, b, width: width, height: height)
        let channels = (0..<3).map { channelSSIM(a, b, width: width, height: height, channel: $0) }
        return min(luma, channels.reduce(0, +) / 3)
    }

    public static func lumaSSIM(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int) -> Double {
        guard width > 0, height > 0 else { return 1 }
        guard a.count == width * height * 4, b.count == a.count else { return 0 }
        return ssim(plane(a, count: width * height, channel: nil), plane(b, count: width * height, channel: nil), width: width, height: height)
    }

    public static func channelSSIM(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, channel: Int) -> Double {
        guard width > 0, height > 0 else { return 1 }
        guard a.count == width * height * 4, b.count == a.count, (0..<3).contains(channel) else { return 0 }
        return ssim(plane(a, count: width * height, channel: channel), plane(b, count: width * height, channel: channel), width: width, height: height)
    }

    private static func plane(_ rgba: [UInt8], count: Int, channel: Int?) -> [Double] {
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            if let channel { out[i] = Double(rgba[i * 4 + channel]) }
            else { out[i] = 0.299 * Double(rgba[i * 4]) + 0.587 * Double(rgba[i * 4 + 1]) + 0.114 * Double(rgba[i * 4 + 2]) }
        }
        return out
    }

    private static func ssim(_ x: [Double], _ y: [Double], width w: Int, height h: Int) -> Double {
        let c1 = 6.5025, c2 = 58.5225   // (0.01 * 255)^2 and (0.03 * 255)^2
        let window = min(8, w, h), step = max(1, window / 2)
        // Summed-area tables of x, y, x^2, y^2 and x*y.
        let stride = w + 1
        var sx = [Double](repeating: 0, count: stride * (h + 1)), sy = sx, sxx = sx, syy = sx, sxy = sx
        for j in 0..<h {
            var rx = 0.0, ry = 0.0, rxx = 0.0, ryy = 0.0, rxy = 0.0
            for i in 0..<w {
                let p = x[j * w + i], q = y[j * w + i]
                rx += p; ry += q; rxx += p * p; ryy += q * q; rxy += p * q
                let o = (j + 1) * stride + i + 1, up = j * stride + i + 1
                sx[o] = sx[up] + rx; sy[o] = sy[up] + ry; sxx[o] = sxx[up] + rxx; syy[o] = syy[up] + ryy; sxy[o] = sxy[up] + rxy
            }
        }
        func box(_ t: [Double], _ x0: Int, _ y0: Int) -> Double {
            t[(y0 + window) * stride + x0 + window] - t[y0 * stride + x0 + window] - t[(y0 + window) * stride + x0] + t[y0 * stride + x0]
        }
        let n = Double(window * window)
        var total = 0.0
        var windows = 0
        var y0 = 0
        while y0 + window <= h {
            var x0 = 0
            while x0 + window <= w {
                let mx = box(sx, x0, y0) / n, my = box(sy, x0, y0) / n
                let vx = box(sxx, x0, y0) / n - mx * mx, vy = box(syy, x0, y0) / n - my * my
                let cov = box(sxy, x0, y0) / n - mx * my
                total += ((2 * mx * my + c1) * (2 * cov + c2)) / ((mx * mx + my * my + c1) * (vx + vy + c2))
                windows += 1
                x0 += step
            }
            y0 += step
        }
        return windows == 0 ? 1 : total / Double(windows)
    }
}
