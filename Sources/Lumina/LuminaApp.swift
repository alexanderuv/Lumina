/// Protocol for Lumina applications using the @main pattern.
///
/// Conform your application struct to this protocol and mark it with @main
/// to create a Lumina application, similar to SwiftUI's App protocol.
///
/// Example:
/// ```swift
/// @main
/// struct HelloWorld: LuminaApp {
///     func configure() throws {
///         var window = try Window.create(
///             title: "Hello, World!",
///             size: LogicalSize(width: 800, height: 600)
///         ).get()
///         window.show()
///     }
/// }
/// ```
@MainActor
public protocol LuminaApp {
    /// Initialize the application.
    ///
    /// Structs get this for free.
    init()

    /// Configure your application windows and initial state.
    ///
    /// This method is called once when your application starts, before the
    /// event loop begins. Create and show your windows here.
    ///
    /// After this method returns, the application event loop runs automatically
    /// until the user quits.
    ///
    /// - Throws: Any errors during application setup
    func configure() async throws
}

// MARK: - Default Implementation

@MainActor
public extension LuminaApp {
    /// Default implementation of configure.
    ///
    /// Override this in your conforming type to set up your application.
    func configure() async throws {
        // Default: do nothing
    }
}

// MARK: - Main Entry Point

@MainActor
public extension LuminaApp {
    /// Main entry point for Lumina applications.
    ///
    /// This is automatically called by the Swift runtime when your app struct
    /// is marked with @main. Do not call this manually.
    static func main() async throws {
        // Create instance of the app
        let appInstance = Self.init()

        // Call configure
        try await appInstance.configure()

        // Create and run the event loop
        var application = try Application()
        try application.run()
    }
}
