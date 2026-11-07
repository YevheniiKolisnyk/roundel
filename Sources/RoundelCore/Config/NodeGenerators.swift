import Foundation

/// Builds the children of a group from something only known at run time (the formats this Mac can write, ...).
/// A group opts in with `"generate": "<id>"`; the result is merged into the config by `ConfigResolver`.
public protocol NodeGenerator: Sendable {
    var id: String { get }
    /// The nodes to add to `group`. Their ids must be unique; prefix them with `group.id`.
    func children(for group: GroupNode) -> [Node]
}

public struct NodeGeneratorRegistry: Sendable {
    private var byID: [String: any NodeGenerator] = [:]

    public init(_ generators: [any NodeGenerator]) {
        for generator in generators where byID[generator.id] == nil { byID[generator.id] = generator }
    }

    public func generator(for id: String) -> (any NodeGenerator)? { byID[id] }

    /// The shipped generators. Adding one = its file + one line here.
    public static func standard(services s: ActionServices) -> NodeGeneratorRegistry {
        NodeGeneratorRegistry([
            ImageConvertFormatsGenerator(capabilities: s.imageCapabilities),
        ])
    }
}

public struct ResolvedConfig: Equatable, Sendable {
    public let config: RoundelConfig
    /// Problems with generated groups (unknown generator, nothing generated). Warnings, never failures.
    public let warnings: [ActionWarning]
}

/// Turns a loaded config into the one the ring is built from: every `generate` group gets its generated children.
/// `config.json` itself is never touched. Resolving an already resolved config changes nothing.
public enum ConfigResolver {
    public static func resolve(_ config: RoundelConfig, generators: NodeGeneratorRegistry) -> ResolvedConfig {
        var warnings: [ActionWarning] = []
        var resolved = config
        resolved.ring = resolve(config.ring, generators: generators, warnings: &warnings)
        return ResolvedConfig(config: resolved, warnings: warnings)
    }

    private static func resolve(_ nodes: [Node], generators: NodeGeneratorRegistry, warnings: inout [ActionWarning]) -> [Node] {
        nodes.map { node in
            guard case .group(var group) = node else { return node }
            group.children = resolve(group.children, generators: generators, warnings: &warnings)

            if let generatorID = group.generate {
                if let generator = generators.generator(for: generatorID) {
                    let taken = Set(group.children.map(\.id))
                    let generated = generator.children(for: group).filter { !taken.contains($0.id) }
                    if generated.isEmpty {
                        warnings.append(ActionWarning(nodeID: group.id, message: "generator '\(generatorID)' produced no items (the group stays empty)"))
                    }
                    group.children += generated
                } else {
                    warnings.append(ActionWarning(nodeID: group.id, message: "unknown generator '\(generatorID)' (the group stays empty)"))
                }
                group.generate = nil
            }
            return .group(group)
        }
    }
}
