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
    ],
    targets: [
        // Pure logic (geometry, interaction state machine, models). No AppKit.
        .target(name: "RoundelCore"),
        .executableTarget(
            name: "Roundel",
            dependencies: [
                "RoundelCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "RoundelCoreTests", dependencies: ["RoundelCore"]),
    ]
)
