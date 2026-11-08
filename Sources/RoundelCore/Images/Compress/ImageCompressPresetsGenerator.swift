import Foundation

/// Fills a group with one `image.compress` action per preset: `"generate": "image.compress.presets"`.
/// The group's `params` `maxDimension`, `stripMetadata` and `dropHDRData` are passed on to all three. A `quality` is not: it would make
/// the presets identical (use a hand-written `image.compress` node for that).
public struct ImageCompressPresetsGenerator: NodeGenerator {
    public let id = "image.compress.presets"

    public init() {}

    /// The titles are too long for a cell next to its icon ("Balanced"), so the cells carry a gauge symbol; the full
    /// name shows in the middle of the ring while the cell is hovered.
    private static let symbols: [CompressionPreset: String] = [
        .light: "gauge.with.dots.needle.33percent", .balanced: "gauge.with.dots.needle.50percent", .strong: "gauge.with.dots.needle.67percent",
    ]

    public func children(for group: GroupNode) -> [Node] {
        let inherited = Params(group.params)
        return CompressionPreset.allCases.map { preset in
            var params: [String: JSONValue] = ["preset": .string(preset.rawValue)]
            if let maxDimension = inherited.int("maxDimension") { params["maxDimension"] = .number(Double(maxDimension)) }
            if let strip = inherited.bool("stripMetadata") { params["stripMetadata"] = .bool(strip) }
            if let drop = inherited.bool("dropHDRData") { params["dropHDRData"] = .bool(drop) }
            return .action(ActionNode(id: "\(group.id).\(preset.rawValue)", title: preset.title, icon: .symbol(Self.symbols[preset] ?? "gauge"),
                                      action: "image.compress", params: .object(params)))
        }
    }
}
