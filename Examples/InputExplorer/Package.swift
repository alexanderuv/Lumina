// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InputExplorer",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "Lumina", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "InputExplorer",
            dependencies: ["Lumina"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
