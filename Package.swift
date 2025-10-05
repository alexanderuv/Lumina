// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Public cross-platform API
        .library(
            name: "Lumina",
            targets: ["Lumina"]
        )
    ],
    targets: [
        // MARK: - Public API

        /// Cross-platform windowing API (includes platform backends via conditional compilation)
        .target(
            name: "Lumina",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Tests

        /// Unit tests (includes platform-specific tests via conditional compilation)
        .testTarget(
            name: "LuminaTests",
            dependencies: ["Lumina"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
