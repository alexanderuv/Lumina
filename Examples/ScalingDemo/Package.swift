// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScalingDemo",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "Lumina", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ScalingDemo",
            dependencies: ["Lumina"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
