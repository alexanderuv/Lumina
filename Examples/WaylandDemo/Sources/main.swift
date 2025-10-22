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
        print("========================================")
        print("WaylandDemo main() ENTRY")
        print("========================================")
        #if LUMINA_WAYLAND
        print("[DEMO] LUMINA_WAYLAND is defined")

        // NEW API: Initialize platform first
        print("[DEMO] Initializing Wayland platform...")
        var platform = try createLinuxPlatform(.wayland)
        print("[DEMO] Platform created successfully")

        // NEW: Monitor enumeration via platform (no app needed!)
        print("[DEMO] Enumerating monitors...")
        do {
            let monitors = try platform.enumerateMonitors()
            print("[DEMO] Found \(monitors.count) monitor(s):")
            for (index, monitor) in monitors.enumerated() {
                print("[DEMO]   [\(index)] \(monitor.name)")
                print("[DEMO]       Position: (\(monitor.position.x), \(monitor.position.y))")
                print("[DEMO]       Size: \(Int(monitor.size.width))×\(Int(monitor.size.height))")
                print("[DEMO]       Scale: \(monitor.scaleFactor)x")
                print("[DEMO]       Primary: \(monitor.isPrimary)")
            }

            let primary = try platform.primaryMonitor()
            print("[DEMO] Primary monitor: \(primary.name)")
        } catch {
            print("[DEMO] ⚠️  Monitor enumeration failed: \(error)")
        }

        // NEW: Create app from platform
        print("[DEMO] Creating application...")
        var app = try platform.createApp()
        print("[DEMO] App created successfully")

        print("[DEMO] About to create window...")
        var window = try app.createWindow(
            title: "Wayland Demo - Native Wayland Window",
            size: LogicalSize(width: 800, height: 600),
            resizable: true,
            monitor: nil as Monitor?
        )
        print("[DEMO] Window createWindow() returned")

        print("[DEMO] Window created, about to call show()")
        window.show()
        print("[DEMO] show() returned")

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✓ Lumina Wayland Demo Running")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✓ Platform/App separation architecture")
        print("✓ Window created with native Wayland protocols")
        print("✓ Using libdecor for decorations")
        print("✓ Light gray window should be visible")
        print("✓ Try resizing the window!")
        print("✓ Close button shows it's working (use Ctrl+C to exit)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

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
