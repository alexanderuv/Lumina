// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WaylandDemo",
    platforms: [
        .macOS(.v15)
    ],
    traits: [
        .default(enabledTraits: ["Wayland"]),
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
            name: "WaylandDemo",
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
