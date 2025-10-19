import Lumina

/// HelloWindow - Minimal window creation example
///
/// Shows the simplest way to create a Lumina application with a window.

@main
struct HelloWindow {
    static func main() throws {
        var app = try createLuminaApp()

        var window = try app.createWindow(
            title: "Hello, Lumina!",
            size: LogicalSize(width: 1000, height: 500),
            resizable: true,
            monitor: nil
        ).get()

        window.show()

        try app.run()
    }
}
