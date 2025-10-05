import Lumina

/// ScalingDemo - DPI and scale factor demonstration

@main
struct ScalingDemo: LuminaApp {
    func configure() throws {
        let logicalSize = LogicalSize(width: 800, height: 600)

        var window = try Window.create(
            title: "Scaling Demo - DPI & Scale Factor",
            size: logicalSize
        ).get()

        window.show()

        let scaleFactor = window.scaleFactor()
        let physicalSize = logicalSize.toPhysical(scaleFactor: scaleFactor)

        print("=== Lumina Scaling Demo ===\n")
        print("Window Information:")
        print("  Logical:  \(logicalSize.width) × \(logicalSize.height) points")
        print("  Physical: \(physicalSize.width) × \(physicalSize.height) pixels")
        print("  Scale:    \(scaleFactor)x\n")
        print("Close window or press Cmd+Q to exit.")
    }
}
