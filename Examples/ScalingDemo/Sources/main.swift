import Lumina

/// ScalingDemo - DPI and scale factor demonstration

@main
struct ScalingDemo {
    static func main() throws {
        // NEW API: Initialize platform first, then create app
        var platform = try createLuminaPlatform()
        var app = try platform.createApp()

        let logicalSize = LogicalSize(width: 800, height: 600)

        var window = try app.createWindow(
            title: "Scaling Demo - DPI & Scale Factor",
            size: logicalSize,
            resizable: true,
            monitor: nil as Monitor?
        )

        window.show()

        let scaleFactor = window.scaleFactor()
        let physicalSize = logicalSize.toPhysical(scaleFactor: scaleFactor)

        print("=== Lumina Scaling Demo ===\n")
        print("Window Information:")
        print("  Logical:  \(logicalSize.width) × \(logicalSize.height) points")
        print("  Physical: \(physicalSize.width) × \(physicalSize.height) pixels")
        print("  Scale:    \(scaleFactor)x\n")
        print("Try moving the window to a display with different DPI!")
        print("Close window or press Cmd+Q to exit.")

        try app.run()
    }
}
