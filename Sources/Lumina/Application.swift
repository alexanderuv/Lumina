/// Cross-platform application and event loop manager.
///
/// Application is the central entry point for Lumina applications. It manages
/// the platform-specific event loop, window lifecycle, and provides a unified
/// interface for handling user input and system events.
///
/// Each application should create exactly one Application instance, which
/// remains valid for the lifetime of the process. The ~Copyable constraint
/// prevents accidental duplication.
///
/// Thread Safety: All Application methods must be called from the main thread.
/// The @MainActor annotation enforces this at compile time.
///
/// Example:
/// ```swift
/// @MainActor
/// func main() async throws {
///     // Create application
///     var app = try Application()
///
///     // Create and show window
///     let window = try Window.create(
///         title: "Hello, Lumina!",
///         size: LogicalSize(width: 800, height: 600)
///     ).get()
///     window.show()
///
///     // Run event loop
///     try app.run()
/// }
/// ```
@MainActor
public struct Application: ~Copyable {
    #if os(macOS)
    private var backend: MacApplication
    #elseif os(Windows)
    private var backend: WinApplication
    #else
    #error("Unsupported platform")
    #endif

    /// Create a new application instance.
    ///
    /// This initializes the platform-specific event loop and application state.
    /// Only one Application instance should exist per process.
    ///
    /// Platform Notes:
    /// - macOS: Initializes NSApplication and sets activation policy
    /// - Windows: Initializes COM and sets DPI awareness
    ///
    /// - Throws: `LuminaError.platformError` if platform initialization fails
    ///
    /// Example:
    /// ```swift
    /// let app = try Application()
    /// ```
    public init() throws {
        #if os(macOS)
        self.backend = try MacApplication()
        #elseif os(Windows)
        self.backend = try WinApplication()
        #endif
    }

    /// Run the event loop until quit (blocking).
    ///
    /// This method blocks the calling thread and processes events continuously
    /// until quit() is called. It's the primary way to run a Lumina application
    /// with a traditional event-driven architecture.
    ///
    /// The event loop will process:
    /// - Window events (resize, close, focus changes)
    /// - Input events (keyboard, mouse, trackpad)
    /// - User-defined events (posted via postUserEvent)
    ///
    /// - Throws: `LuminaError.eventLoopFailed` if the event loop encounters
    ///           an unrecoverable error
    ///
    /// Example:
    /// ```swift
    /// var app = try Application()
    /// let window = try Window.create(
    ///     title: "App",
    ///     size: LogicalSize(width: 800, height: 600)
    /// ).get()
    /// window.show()
    ///
    /// try app.run()  // Blocks until quit() is called
    /// ```
    public mutating func run() throws {
        try backend.run()
    }

    /// Poll for events without blocking.
    ///
    /// Processes all currently pending events and returns immediately. This
    /// is useful for applications with custom render loops (games, simulations)
    /// that need to maintain a consistent frame rate while processing input.
    ///
    /// - Returns: `true` if any events were processed, `false` if the queue was empty
    /// - Throws: `LuminaError.eventLoopFailed` if polling fails
    ///
    /// Example:
    /// ```swift
    /// var app = try Application()
    /// let window = try Window.create(
    ///     title: "Game",
    ///     size: LogicalSize(width: 1920, height: 1080)
    /// ).get()
    /// window.show()
    ///
    /// // Custom game loop
    /// while !shouldQuit {
    ///     // Process events
    ///     _ = try app.poll()
    ///
    ///     // Update game state
    ///     updateGame(deltaTime)
    ///
    ///     // Render frame
    ///     renderFrame()
    /// }
    /// ```
    public mutating func poll() throws -> Bool {
        try backend.poll()
    }

    /// Wait for the next event (low-power sleep).
    ///
    /// Puts the thread to sleep until an event arrives, then returns without
    /// processing the event. This is useful for idle loops that don't need
    /// continuous polling, reducing CPU usage when no events are arriving.
    ///
    /// After wait() returns, call poll() or run() to process the event.
    ///
    /// Platform Notes:
    /// - macOS: Uses CFRunLoop for efficient power management
    /// - Windows: Uses WaitMessage for low-power wait
    ///
    /// - Throws: `LuminaError.eventLoopFailed` if wait fails
    ///
    /// Example:
    /// ```swift
    /// var app = try Application()
    /// let window = try Window.create(
    ///     title: "Editor",
    ///     size: LogicalSize(width: 1024, height: 768)
    /// ).get()
    /// window.show()
    ///
    /// // Efficient idle loop
    /// while !shouldQuit {
    ///     try app.wait()      // Sleep until event arrives
    ///     _ = try app.poll()  // Process the event
    /// }
    /// ```
    public mutating func wait() throws {
        try backend.wait()
    }

    /// Post a user-defined event to the event queue (thread-safe).
    ///
    /// This method allows background threads to communicate with the main
    /// event loop by posting custom events. The event will be delivered
    /// during the next event loop iteration.
    ///
    /// Thread Safety: This is the ONLY Application method that's safe to
    /// call from background threads.
    ///
    /// - Parameter event: The user event to post
    ///
    /// Example:
    /// ```swift
    /// @MainActor
    /// var app = Application()
    ///
    /// // Background thread posts event
    /// Task.detached {
    ///     let result = await performNetworkRequest()
    ///     await app.postUserEvent(UserEvent(result))
    /// }
    ///
    /// // Main thread receives event in event loop
    /// // (Event handling API to be added in future milestone)
    /// ```
    nonisolated public func postUserEvent(_ event: UserEvent) {
        backend.postUserEvent(event)
    }

    /// Request application termination.
    ///
    /// Signals the event loop to exit after processing current events.
    /// The run() method will return after this is called.
    ///
    /// This method is idempotent (safe to call multiple times).
    ///
    /// Example:
    /// ```swift
    /// var app = try Application()
    /// let window = try Window.create(
    ///     title: "App",
    ///     size: LogicalSize(width: 800, height: 600)
    /// ).get()
    /// window.show()
    ///
    /// // Quit when window closes
    /// // (Window close handling to be added in future milestone)
    /// app.quit()
    ///
    /// try app.run()  // Will return immediately
    /// ```
    public func quit() {
        backend.quit()
    }
}
