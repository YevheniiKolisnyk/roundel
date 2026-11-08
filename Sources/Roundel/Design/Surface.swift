import SwiftUI
import RoundelCore

/// The accessibility settings, the preference and the platform, resolved to what a surface should be.
struct SurfaceInfo: DynamicProperty {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.surfacePreference) private var preference
    @Environment(\.surfaceOverrides) private var overrides

    var reduceTransparency: Bool { overrides.reduceTransparency ?? systemReduceTransparency }
    var increaseContrast: Bool { overrides.increaseContrast ?? (systemContrast == .increased) }
    var reduceMotion: Bool { overrides.reduceMotion ?? systemReduceMotion }

    var style: SurfaceStyle {
        SurfaceStyle.resolve(preference: preference, glassAvailable: Platform.supportsGlass, reduceTransparency: reduceTransparency)
    }

    var traits: SurfaceTraits { SurfaceTraits.make(style: style, increaseContrast: increaseContrast) }
}

/// Draws a shape as a surface: Liquid Glass, a Material with a lit edge and a soft shadow, or a solid color. The three
/// are separate, complete looks; the Material one is the one macOS 14 and 15 show (and `ROUNDEL_SURFACE=material` forces).
private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Whether the material and solid looks cast a shadow (a ring's bands are close together and do not).
    let casting: Bool
    private let info = SurfaceInfo()
    @Environment(\.colorScheme) private var scheme
    private let metrics = DesignMetrics.standard

    func body(content: Content) -> some View {
        let style = info.style
        let traits = info.traits
        switch style {
        case .glass: glass(content, traits)
        case .material: material(content, traits)
        case .solid: solid(content, traits)
        }
    }

    // MARK: The three looks

    @ViewBuilder
    private func glass(_ content: Content, _ traits: SurfaceTraits) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(traits.borderOpacity), lineWidth: traits.borderWidth) }
        } else {
            material(content, traits)   // cannot happen: `resolve` only returns glass where it exists
        }
    }

    private func material(_ content: Content, _ traits: SurfaceTraits) -> some View {
        content
            .background { shape.fill(.regularMaterial) }
            .overlay { shape.strokeBorder(litEdge(traits), lineWidth: traits.borderWidth) }
            .shadow(color: .black.opacity(casting ? metrics.shadowOpacity : 0), radius: metrics.shadowRadius, x: 0, y: metrics.shadowYOffset)
    }

    private func solid(_ content: Content, _ traits: SurfaceTraits) -> some View {
        content
            .background { shape.fill(Color(nsColor: .windowBackgroundColor)) }
            .overlay { shape.strokeBorder(Color.primary.opacity(traits.borderOpacity), lineWidth: traits.borderWidth) }
            .shadow(color: .black.opacity(casting ? metrics.shadowOpacity : 0), radius: metrics.shadowRadius, x: 0, y: metrics.shadowYOffset)
    }

    /// A hairline that is lit from above: bright at the top edge, faint at the bottom.
    private func litEdge(_ traits: SurfaceTraits) -> LinearGradient {
        let top = scheme == .dark ? min(1, traits.borderOpacity * 2) : min(1, 0.5 + traits.borderOpacity)
        return LinearGradient(colors: [Color.white.opacity(top), Color.primary.opacity(traits.borderOpacity * 0.6)], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// Draws this view on a surface in `shape`: glass, material or solid, as the system and the settings say.
    func roundelSurface<S: InsettableShape>(in shape: S, casting: Bool = true) -> some View {
        modifier(SurfaceModifier(shape: shape, casting: casting))
    }
}
