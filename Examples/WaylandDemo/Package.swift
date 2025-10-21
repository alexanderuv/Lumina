// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WaylandDemo",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "Lumina", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WaylandDemo",
            dependencies: ["Lumina"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
                // Note: LUMINA_WAYLAND must be passed at build time:
                // swift build -Xswiftc -DLUMINA_WAYLAND
            ]
        )
    ]
)
