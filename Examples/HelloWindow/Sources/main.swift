import Lumina

/// HelloWindow - Minimal window creation example
///
/// Shows the simplest way to create a Lumina application with a window.

@main
struct HelloWindow {
    static func main() throws {
        // Initialize platform first, then create app
        let platform = try createLuminaPlatform()
        var app = try platform.createApp()

        var window = try app.createWindow(
            title: "Hello, Lumina!",
            size: LogicalSize(width: 1000, height: 500),
            resizable: true,
            monitor: nil as Monitor?
        )

        window.show()

        try app.run()
    }
}
