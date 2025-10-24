// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ScalingDemo",
    platforms: [
        .macOS(.v15)
    ],
    traits: [
        .trait(name: "Wayland", description: "Enable Wayland backend support")
    ],
    dependencies: [
        .package(
            name: "Lumina",
            path: "../..",
            traits: [
                .defaults,
                .init(name: "Wayland", condition: .when(traits: ["Wayland"]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "ScalingDemo",
            dependencies: ["Lumina"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .define("LUMINA_WAYLAND", .when(traits: ["Wayland"]))
            ]
        )
    ]
)
