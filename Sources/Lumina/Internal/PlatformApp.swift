/// Protocol for platform-specific application implementations.
///
/// This protocol defines the contract that platform backends (macOS, Windows)
/// must implement to provide application initialization and event loop functionality.
///
/// Platform implementations handle:
/// - Platform-specific initialization (DPI awareness, COM, NSApplication setup)
/// - Event loop management (run, poll, wait modes)
/// - User event posting and processing
/// - Application lifecycle (quit)
///
/// Thread Safety: All methods must be called from the main thread (@MainActor).
/// The postUserEvent method must be thread-safe for cross-thread communication.
///
/// Platform Implementations:
/// - macOS: Uses NSApp.nextEvent, CFRunLoop for wait mode
/// - Windows: Uses GetMessage/PeekMessage/DispatchMessage, WaitMessage for wait mode
@MainActor
public protocol PlatformApp: Sendable {
    /// Initialize the platform-specific application.
    ///
    /// This is where platform-specific initialization occurs, including:
    /// - Windows: DPI awareness, COM initialization
    /// - macOS: NSApplication setup, activation policy
    ///
    /// IMPORTANT: This must happen BEFORE any window creation or UI operations.
    ///
    /// - Throws: `LuminaError.platformError` if platform initialization fails
    init() throws

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

    /// Poll for events without blocking.
    ///
    /// Processes all currently pending events and returns immediately.
    /// This is used for non-blocking event processing in game loops or
    /// custom render loops.
    ///
    /// - Returns: `true` if any events were processed, `false` if the queue was empty
    /// - Throws: `LuminaError.eventLoopFailed` if polling fails
    mutating func poll() throws -> Bool

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

    /// Post a user-defined event to the event queue (thread-safe).
    ///
    /// This method is thread-safe and allows background threads to communicate
    /// with the main event loop by posting custom events. The event will be
    /// delivered during the next event loop iteration.
    ///
    /// Thread Safety: This is the ONLY method that's safe to call from
    /// background threads.
    ///
    /// - Parameter event: The user event to post
    nonisolated func postUserEvent(_ event: UserEvent)

    /// Request event loop termination.
    ///
    /// Signals the event loop to exit after processing current events.
    /// The run() method should return after this is called.
    ///
    /// This method is idempotent (safe to call multiple times).
    func quit()
}
