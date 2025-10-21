#if os(Linux)
import Lumina

/// WaylandDemo - Explicit Wayland backend example
///
/// This example demonstrates how to force the Wayland backend on Linux,
/// which can be useful for:
/// - Testing Wayland-specific features
/// - Ensuring consistent behavior across development environments
/// - Debugging Wayland compositor integration
/// - Leveraging Wayland-exclusive features (client-side decorations, etc.)
///
/// **Build Requirements:**
/// This example requires Lumina to be compiled with LUMINA_WAYLAND support.
/// Build from the repository root with:
/// ```bash
/// swift build -Xswiftc -DLUMINA_WAYLAND
/// cd Examples/WaylandDemo
/// swift run -Xswiftc -DLUMINA_WAYLAND
/// ```
///
/// Or use the provided build script:
/// ```bash
/// ./build-wayland.sh
/// ```
///
/// **Runtime Requirements:**
/// - A Wayland compositor must be running (GNOME, KDE Plasma, Sway, etc.)
/// - WAYLAND_DISPLAY environment variable should be set
///
/// **Usage:**
/// This example creates a window using the Wayland backend explicitly,
/// bypassing the automatic backend detection that would normally try
/// Wayland first and fall back to X11.

@main
struct WaylandDemo {
    static func main() throws {
        #if LUMINA_WAYLAND
        // Force Wayland backend - will fail if Wayland is not available
        var app = try createLuminaApp(.wayland)

        var window = try app.createWindow(
            title: "Wayland Demo - Native Wayland Window",
            size: LogicalSize(width: 800, height: 600),
            resizable: true,
            monitor: nil
        )

        window.show()

        print("✓ Running on Wayland backend")
        print("✓ This window is using native Wayland protocols")
        print("✓ Press Ctrl+C or close the window to exit")

        try app.run()
        #else
        print("❌ Error: LUMINA_WAYLAND is not defined")
        print("")
        print("This example requires Lumina to be compiled with Wayland support.")
        print("")
        print("To build and run with Wayland support:")
        print("  cd Examples/WaylandDemo")
        print("  ./build-wayland.sh")
        print("")
        print("Or manually:")
        print("  swift run -Xswiftc -DLUMINA_WAYLAND")
        #endif
    }
}
#else
// This example only works on Linux
import Foundation

@main
struct WaylandDemo {
    static func main() {
        print("WaylandDemo is only available on Linux")
        print("This example demonstrates explicit Wayland backend selection")
    }
}
#endif
