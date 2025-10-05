// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PerformanceTest",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "Lumina", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "PerformanceTest",
            dependencies: ["Lumina"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
