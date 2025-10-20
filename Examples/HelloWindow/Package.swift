// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HelloWindow",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "Lumina", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "HelloWindow",
            dependencies: ["Lumina"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
