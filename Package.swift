// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v15)   // macOS 15 (Sequoia) minimum
        // Linux doesn't need explicit platform declaration
    ],
    products: [
        // Public cross-platform API
        .library(
            name: "Lumina",
            targets: ["Lumina"]
        ),
    ],
    traits: [
        .trait(
            name: "Wayland",
            description: "Enable Wayland backend support on Linux"
        )
    ],
    dependencies: [
        // Swift Logging API
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [
        // MARK: - Public API

        /// Cross-platform windowing API (includes platform backends via conditional compilation)
        .target(
            name: "Lumina",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .target(name: "CXCBLinux", condition: .when(platforms: [.linux])),
                .target(name: "CWaylandClient", condition: .when(traits: ["Wayland"]))
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .define("LUMINA_X11", .when(platforms: [.linux])),
                .define("LUMINA_WAYLAND", .when(traits: ["Wayland"]))
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

        /// Wayland client bindings for Linux Wayland support
        /// Protocol bindings generated via: swift package plugin generate-wayland-protocols
        .target(
            name: "CWaylandClient",
            path: "Sources/CInterop/CWaylandClient",
            // NO explicit sources - auto-discover all .c files
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedLibrary("wayland-client"),
                .linkedLibrary("wayland-egl"),
                .linkedLibrary("xkbcommon")
                // libdecor is dynamically loaded at runtime
            ]
        ),

        // MARK: - Build Plugins

        /// Command plugin to generate Wayland protocol bindings from XML
        /// Usage: swift package plugin generate-wayland-protocols
        .plugin(
            name: "generate-wayland-protocols",
            capability: .command(
                intent: .custom(
                    verb: "generate-wayland-protocols",
                    description: "Generate Wayland protocol C bindings from XML using wayland-scanner"
                )
            )
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
