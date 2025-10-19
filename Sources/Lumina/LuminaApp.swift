/// Protocol for Lumina applications using the @main pattern.
///
/// Conform your application struct to this protocol and mark it with @main
/// to create a Lumina application, similar to SwiftUI's App protocol.
///
/// The simplest way is to use the platform-provided `PlatformBackend` type,
/// which automatically conforms to LuminaApp:
///
/// Example:
/// ```swift
/// @main
/// extension PlatformBackend {
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
    ///
    /// Execution order:
    /// 1. Create app instance (platform init happens in init() - DPI awareness, COM, etc.)
    /// 2. Call configure() (create windows - DPI is already set)
    /// 3. Run event loop (process events until quit)
    static func main() async {
        do {
            // Create instance of the app
            // Platform initialization (DPI awareness, COM, etc.) happens HERE in init()
            let app = Self.init()
            var platformApp = try PlatformBackend()

            // Call configure to set up windows
            // DPI is already set at this point
            try await app.configure()

            // Run the event loop
            try platformApp.run()
        } catch {
            // Handle initialization or runtime errors
            // Print detailed error information for debugging
            print("Fatal error: \(error)")
            print("Error type: \(type(of: error))")

            // Terminate with clear error message
            fatalError("Lumina initialization failed: \(error)")
        }
    }
}
