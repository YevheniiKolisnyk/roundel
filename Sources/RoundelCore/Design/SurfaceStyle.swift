import Foundation

/// What a surface (a toast card, a ring band) is made of.
public enum SurfaceStyle: Equatable, Sendable {
    /// Liquid Glass (macOS 26 and later).
    case glass
    /// A system Material: what macOS 14 and 15 show.
    case material
    /// An opaque color: Reduce Transparency.
    case solid
}

/// What the user (or a developer, with `ROUNDEL_SURFACE`) asked for.
public enum SurfacePreference: String, Equatable, Sendable {
    case automatic, glass, material, solid

    /// The value of the `ROUNDEL_SURFACE` environment variable; anything unknown means automatic.
    public static func parse(_ value: String?) -> SurfacePreference {
        guard let value else { return .automatic }
        return SurfacePreference(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .automatic
    }
}

extension SurfaceStyle {
    /// Reduce Transparency always wins, because it is an accessibility setting. Otherwise the preference decides;
    /// automatic means glass where the system has it and the Material look everywhere else.
    ///
    /// The Material look an older system shows and the one `ROUNDEL_SURFACE=material` forces on a newer system are the
    /// same result of this function, so the switch exercises exactly what an older system would draw.
    public static func resolve(preference: SurfacePreference, glassAvailable: Bool, reduceTransparency: Bool) -> SurfaceStyle {
        if reduceTransparency || preference == .solid { return .solid }
        switch preference {
        case .material: return .material
        case .glass, .automatic: return glassAvailable ? .glass : .material
        case .solid: return .solid
        }
    }
}

/// The edge and text strengths that go with a surface style and the Increased Contrast setting.
public struct SurfaceTraits: Equatable, Sendable {
    public var borderWidth: Double
    public var borderOpacity: Double
    /// How strong secondary text is drawn (1 = as primary).
    public var secondaryTextOpacity: Double

    public static func make(style: SurfaceStyle, increaseContrast: Bool, metrics: DesignMetrics = .standard) -> SurfaceTraits {
        let edge: Double
        switch (style, increaseContrast) {
        case (.glass, false): edge = 0.10
        case (.material, false): edge = 0.14
        case (.solid, false): edge = 0.20   // no blur to set it apart from what is behind
        case (.glass, true): edge = 0.35
        case (.material, true): edge = 0.40
        case (.solid, true): edge = 0.50
        }
        return SurfaceTraits(
            borderWidth: increaseContrast ? metrics.borderWidthIncreasedContrast : metrics.borderWidth,
            borderOpacity: edge,
            secondaryTextOpacity: increaseContrast ? 0.85 : 0.62
        )
    }
}
