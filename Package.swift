// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Roundel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Roundel", targets: ["Roundel"]),
    ],
    dependencies: [
        // Global hotkey registration + recorder UI + shortcut storage.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
        // WebP encoding (ImageIO cannot write WebP). Compiled from source and linked statically; only the encoder is used.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode", .upToNextMinor(from: "1.6.0")),
    ],
    targets: [
        // Pure logic (geometry, interaction state machine, models). No AppKit.
        .target(name: "RoundelCore"),
        // The libwebp-based ImageEncoder. Kept apart so RoundelCore stays free of third-party code.
        .target(
            name: "RoundelWebP",
            dependencies: [
                "RoundelCore",
                .product(name: "libwebp", package: "libwebp-Xcode"),
            ]
        ),
        .executableTarget(
            name: "Roundel",
            dependencies: [
                "RoundelCore",
                "RoundelWebP",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "RoundelCoreTests", dependencies: ["RoundelCore"]),
        .testTarget(name: "RoundelWebPTests", dependencies: ["RoundelWebP", "RoundelCore"]),
    ]
)
