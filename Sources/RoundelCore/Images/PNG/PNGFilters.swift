import Foundation

/// PNG's per-row prediction filters, both ways. Rows are `rowBytes` long; `step` is the byte distance to the pixel on the left.
enum PNGFilter {
    enum Strategy: CaseIterable, Equatable {
        case none, sub, up, average, paeth
        /// Each row gets whichever filter makes its bytes look smallest (the libpng heuristic: least sum of absolute values).
        case adaptive

        /// The filter type byte of a fixed strategy.
        var fixedType: UInt8? {
            switch self {
            case .none: 0
            case .sub: 1
            case .up: 2
            case .average: 3
            case .paeth: 4
            case .adaptive: nil
            }
        }
    }

    // MARK: Undo

    /// The rows of pixel bytes (`height * rowBytes`) from filtered data (`height * (rowBytes + 1)`); `nil` if the size is
    /// wrong or a row names a filter that does not exist.
    static func unfilter(_ filtered: [UInt8], rowBytes: Int, height: Int, step: Int) -> [UInt8]? {
        guard rowBytes > 0, height > 0, filtered.count == height * (rowBytes + 1) else { return nil }
        var out = [UInt8](repeating: 0, count: height * rowBytes)
        var valid = true
        filtered.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for row in 0..<height {
                    let type = src[row * (rowBytes + 1)]
                    guard type <= 4 else { valid = false; return }
                    let s = row * (rowBytes + 1) + 1
                    let d = row * rowBytes
                    for i in 0..<rowBytes {
                        let x = Int(src[s + i])
                        let a = i >= step ? Int(dst[d + i - step]) : 0
                        let b = row > 0 ? Int(dst[d - rowBytes + i]) : 0
                        let c = (row > 0 && i >= step) ? Int(dst[d - rowBytes + i - step]) : 0
                        let predicted: Int
                        switch type {
                        case 0: predicted = 0
                        case 1: predicted = a
                        case 2: predicted = b
                        case 3: predicted = (a + b) / 2
                        default: predicted = paeth(a, b, c)
                        }
                        dst[d + i] = UInt8(truncatingIfNeeded: x + predicted)
                    }
                }
            }
        }
        return valid ? out : nil
    }

    // MARK: Apply

    /// Filtered rows (type byte first) for `strategy`.
    static func filter(_ pixels: [UInt8], rowBytes: Int, height: Int, step: Int, strategy: Strategy) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: height * (rowBytes + 1))
        var scratch = [[UInt8]](repeating: [UInt8](repeating: 0, count: rowBytes), count: 5)
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for row in 0..<height {
                    let d = row * (rowBytes + 1)
                    let current = row * rowBytes
                    let previous = row > 0 ? (row - 1) * rowBytes : -1
                    if let fixed = strategy.fixedType {
                        dst[d] = fixed
                        encodeRow(type: fixed, src: src, current: current, previous: previous, rowBytes: rowBytes, step: step) { dst[d + 1 + $0] = $1 }
                    } else {
                        var bestType: UInt8 = 0
                        var bestScore = Int.max
                        for type in 0..<5 {
                            var score = 0
                            encodeRow(type: UInt8(type), src: src, current: current, previous: previous, rowBytes: rowBytes, step: step) { index, value in
                                scratch[type][index] = value
                                score += Int(value < 128 ? value : 255 - value &+ 1)   // |signed byte|
                            }
                            if score < bestScore { bestScore = score; bestType = UInt8(type) }
                        }
                        dst[d] = bestType
                        for i in 0..<rowBytes { dst[d + 1 + i] = scratch[Int(bestType)][i] }
                    }
                }
            }
        }
        return out
    }

    private static func encodeRow(type: UInt8, src: UnsafeBufferPointer<UInt8>, current: Int, previous: Int, rowBytes: Int, step: Int,
                                  emit: (Int, UInt8) -> Void) {
        for i in 0..<rowBytes {
            let x = Int(src[current + i])
            let a = i >= step ? Int(src[current + i - step]) : 0
            let b = previous >= 0 ? Int(src[previous + i]) : 0
            let c = (previous >= 0 && i >= step) ? Int(src[previous + i - step]) : 0
            let predicted: Int
            switch type {
            case 0: predicted = 0
            case 1: predicted = a
            case 2: predicted = b
            case 3: predicted = (a + b) / 2
            default: predicted = paeth(a, b, c)
            }
            emit(i, UInt8(truncatingIfNeeded: x - predicted))
        }
    }

    static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }
}
