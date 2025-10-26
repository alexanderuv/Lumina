/// Callback invoked when a window is closed.
///
/// This is used internally by the platform layer to notify the Application
/// when a window has been closed, allowing it to clean up the window registry.
internal typealias WindowCloseCallback = @MainActor @Sendable (WindowID) -> Void

/// Protocol for Lumina applications.
///
/// This is the main entry point for creating Lumina applications. Create an instance
/// of a type conforming to this protocol to start your application.
///
/// Example usage:
/// ```swift
/// @main
/// struct MyApp {
///     static func main() async throws {
///         var app = try LuminaApp()
///         var window = try app.createWindow(
///             title: "Hello, Lumina!",
///             size: LogicalSize(width: 800, height: 600),
///             resizable: true,
///             monitor: nil
///         ).get()
///         window.show()
///         try app.run()
///     }
/// }
/// ```
///
/// For custom event loops:
/// ```swift
/// var running = true
/// while running {
///     while let event = try app.poll() {
///         if case .window(.closed) = event {
///             running = false
///         }
///     }
///     // Game logic and rendering
/// }
/// ```
///
/// Thread Safety: All methods must be called from the main thread (@MainActor).
/// The postUserEvent method is the only exception - it's thread-safe.
@MainActor
public protocol LuminaApp: Sendable, ~Copyable {
    /// The platform-specific window type (platform-specific window structs)
    /// Windows use non-copyable semantics to ensure proper resource management
    associatedtype Window: LuminaWindow

    /// Run the event loop until quit (blocking).
    ///
    /// This method blocks the calling thread and processes events continuously
    /// until quit() is called. It should return when the application is ready
    /// to terminate.
    ///
    /// The event loop processes:
    /// - Window events (resize, close, focus changes)
    /// - Input events (keyboard, mouse, trackpad)
    /// - User-defined events (posted via postUserEvent)
    ///
    /// - Throws: `LuminaError.eventLoopFailed` if the event loop encounters
    ///           an unrecoverable error
    mutating func run() throws

    /// Poll for the next event without blocking.
    ///
    /// Returns the next pending event and removes it from the queue, or returns
    /// `nil` if no events are available. This enables non-blocking event
    /// processing for custom game loops and render loops.
    ///
    /// Example usage:
    /// ```swift
    /// var running = true
    /// while running {
    ///     while let event = try platform.poll() {
    ///         if case .window(.closed) = event {
    ///             running = false
    ///         }
    ///     }
    ///     // Game logic and rendering
    /// }
    /// ```
    ///
    /// - Returns: The next event from the queue, or `nil` if no events are pending
    /// - Throws: `LuminaError.eventLoopFailed` if polling fails
    mutating func poll() throws -> Event?

    /// Wait for the next event (low-power sleep).
    ///
    /// Puts the thread to sleep until an event arrives, then returns without
    /// processing the event. This is used for efficient idle loops that don't
    /// need continuous polling.
    ///
    /// After wait() returns, call poll() or run() to process the event.
    ///
    /// Platform Notes:
    /// - macOS: Uses CFRunLoop with infinite timeout
    /// - Windows: Uses WaitMessage() or MsgWaitForMultipleObjects()
    ///
    /// - Throws: `LuminaError.eventLoopFailed` if wait fails
    mutating func wait() throws

    /// Pump events with specified control flow mode.
    ///
    /// This is the core event processing method that supports different control flow modes:
    /// - `.wait`: Block until an event arrives (efficient for UI apps)
    /// - `.poll`: Return immediately with any pending events (efficient for games)
    /// - `.waitUntil(deadline)`: Block with timeout (efficient for animations)
    ///
    /// The run(), poll(), and wait() methods are convenience wrappers around pumpEvents().
    ///
    /// Example:
    /// ```swift
    /// // Game loop with 60fps frame pacing
    /// loop {
    ///     let deadline = Deadline(seconds: 1.0 / 60.0)
    ///     while let event = app.pumpEvents(mode: .waitUntil(deadline)) {
    ///         handleEvent(event)
    ///     }
    ///     render()
    /// }
    ///
    /// // UI application: block until events
    /// while let event = app.pumpEvents(mode: .wait) {
    ///     handleEvent(event)
    /// }
    /// ```
    ///
    /// - Parameter mode: The control flow mode (default: .wait)
    /// - Returns: The next event, or nil if no events are available
    /// - Throws: `LuminaError.eventLoopFailed` if event processing fails
    mutating func pumpEvents(mode: ControlFlowMode) -> Event?

    /// Post a user-defined event to the event queue.
    ///
    /// Posts a custom event to the main event loop. The event will be
    /// delivered during the next event loop iteration in FIFO order.
    ///
    /// Background threads must use `await` to call this method:
    /// ```swift
    /// Task {
    ///     await app.postUserEvent(.custom("data"))
    /// }
    /// ```
    ///
    /// - Parameter event: The user event to post
    func postUserEvent(_ event: UserEvent)

    /// Request event loop termination.
    ///
    /// Signals the event loop to exit after processing current events.
    /// The run() method should return after this is called.
    ///
    /// This method is idempotent (safe to call multiple times).
    mutating func quit()

    /// Create a new window and register it with the application.
    ///
    /// This is the only way to create windows - it ensures the application
    /// tracks all windows for event routing and lifecycle management.
    ///
    /// - Parameters:
    ///   - title: Window title
    ///   - size: Initial window content size in logical pixels
    ///   - resizable: Whether the window can be resized by the user
    ///   - monitor: Optional monitor to place the window on
    /// - Returns: The created window
    /// - Throws: LuminaError if window creation fails
    mutating func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> Window

    /// Whether the application should quit when the last window is closed.
    ///
    /// Defaults to `true`. Set to `false` if you want the application to
    /// continue running in the background after all windows are closed.
    var exitOnLastWindowClosed: Bool { get set }
}

