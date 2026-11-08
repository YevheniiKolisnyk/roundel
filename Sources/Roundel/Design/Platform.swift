import SwiftUI
import RoundelCore

enum Platform {
    /// Liquid Glass exists from macOS 26.
    static var supportsGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension SurfacePreference {
    /// `ROUNDEL_SURFACE=material` (the look macOS 14-15 shows) or `=solid` (the Reduce Transparency look), for looking at
    /// those looks on a newer system without changing system settings.
    static var fromProcessEnvironment: SurfacePreference {
        parse(ProcessInfo.processInfo.environment["ROUNDEL_SURFACE"])
    }
}

/// Settings that normally come from the system, overridable for renders and tests. `nil` = ask the system.
struct SurfaceOverrides: Equatable {
    var reduceTransparency: Bool?
    var increaseContrast: Bool?
    var reduceMotion: Bool?
}

private struct SurfacePreferenceKey: EnvironmentKey {
    static let defaultValue = SurfacePreference.fromProcessEnvironment
}

private struct SurfaceOverridesKey: EnvironmentKey {
    static let defaultValue = SurfaceOverrides()
}

extension EnvironmentValues {
    var surfacePreference: SurfacePreference {
        get { self[SurfacePreferenceKey.self] }
        set { self[SurfacePreferenceKey.self] = newValue }
    }

    var surfaceOverrides: SurfaceOverrides {
        get { self[SurfaceOverridesKey.self] }
        set { self[SurfaceOverridesKey.self] = newValue }
    }
}

extension MotionSpec {
    var animation: Animation {
        switch self {
        case .spring(let response, let dampingFraction): .spring(response: response, dampingFraction: dampingFraction)
        case .fade(let duration): .easeInOut(duration: duration)
        case .easeOut(let duration): .easeOut(duration: duration)
        }
    }
}
