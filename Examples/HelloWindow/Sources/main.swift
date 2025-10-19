import Lumina

/// HelloWindow - Minimal window creation example
///
/// Just implement configure() to set up your windows.
/// The framework handles everything else.

@main
struct HelloWindow: LuminaApp {
    func configure() throws {
        var window = try Window.create(
            title: "Hello, Lumina!",
            size: LogicalSize(width: 1000, height: 500)
        ).get()

        window.show()
    }
}
