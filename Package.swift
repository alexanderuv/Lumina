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
            dependencies: [
                .target(name: "CXCBLinux", condition: .when(platforms: [.linux]))
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - C Interop (Linux)

        /// XCB bindings for Linux X11 support
        .systemLibrary(
            name: "CXCBLinux",
            path: "Sources/CInterop/CXCBLinux",
            pkgConfig: "xcb xcb-keysyms xcb-xkb xcb-xinput xcb-randr xkbcommon xkbcommon-x11",
            providers: [
                .apt(["libxcb1-dev", "libxcb-keysyms1-dev", "libxcb-xkb-dev",
                      "libxcb-xinput-dev", "libxcb-randr0-dev",
                      "libxkbcommon-dev", "libxkbcommon-x11-dev"]),
                .yum(["libxcb-devel", "xcb-util-keysyms-devel",
                      "libxkbcommon-devel", "libxkbcommon-x11-devel"])
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
