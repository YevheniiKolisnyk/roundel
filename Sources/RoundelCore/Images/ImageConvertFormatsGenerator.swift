import Foundation

/// Fills a group with one `image.convert` action per format this Mac can write: `"generate": "image.convert.formats"`.
/// The group's `params.quality` (0-1) is passed on to the lossy formats.
public struct ImageConvertFormatsGenerator: NodeGenerator {
    public let id = "image.convert.formats"
    private let capabilities: any ImageCapabilities

    public init(capabilities: any ImageCapabilities) {
        self.capabilities = capabilities
    }

    public func children(for group: GroupNode) -> [Node] {
        let quality = Params(group.params).double("quality")
        return ImageFormats.available(writable: capabilities.writableTypeIdentifiers).map { format in
            var params: [String: JSONValue] = ["format": .string(format.key)]
            if format.isLossy, let quality { params["quality"] = .number(quality) }
            return .action(ActionNode(id: "\(group.id).\(format.key)", title: format.displayName, icon: .text(format.displayName),
                                      action: "image.convert", params: .object(params)))
        }
    }
}
