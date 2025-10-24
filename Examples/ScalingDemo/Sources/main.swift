import Lumina

/// ScalingDemo - DPI and scale factor demonstration

@main
struct ScalingDemo {
    static func main() throws {
        // Initialize platform first, then create app
        var platform = try createLuminaPlatform()

        // Print monitor information before creating window
        print("=== Lumina Scaling & Monitor Demo ===\n")
        print("📺 Detected Monitors:")

        let monitors = try platform.enumerateMonitors()
        for (index, monitor) in monitors.enumerated() {
            let prefix = monitor.isPrimary ? "⭐" : "  "
            print("\(prefix) Monitor \(index + 1): \(monitor.name)")
            print("     Position: (\(Int(monitor.position.x)), \(Int(monitor.position.y)))")
            print("     Size: \(Int(monitor.size.width)) × \(Int(monitor.size.height)) logical")
            print("     Scale: \(monitor.scaleFactor)x")
            let physicalWidth = Int(Float(monitor.size.width) * monitor.scaleFactor)
            let physicalHeight = Int(Float(monitor.size.height) * monitor.scaleFactor)
            print("     Physical: \(physicalWidth) × \(physicalHeight) pixels\n")
        }

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

        print("🪟 Window Information:")
        print("  Logical:  \(logicalSize.width) × \(logicalSize.height) points")
        print("  Physical: \(physicalSize.width) × \(physicalSize.height) pixels")
        print("  Scale:    \(scaleFactor)x\n")
        print("Try moving the window to a display with different DPI!")
        print("Close window or press Cmd+Q to exit.")

        try app.run()
    }
}
