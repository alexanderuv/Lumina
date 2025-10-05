/// Internal protocol for platform-specific event loop implementations.
///
/// This protocol is NOT part of the public API. It defines the contract
/// that platform backends (macOS, Windows) must implement to provide
/// event loop functionality.
///
/// Thread Safety: All methods must be called from the main thread (@MainActor).
/// The postUserEvent method must be thread-safe for cross-thread communication.
///
/// Platform Implementations:
/// - macOS: Uses NSApp.nextEvent, CFRunLoop for wait mode
/// - Windows: Uses GetMessage/PeekMessage/DispatchMessage, WaitMessage for wait mode
@MainActor
internal protocol EventLoopBackend: Sendable {
    /// Run the event loop until quit (blocking).
    ///
    /// This method blocks the calling thread and processes events continuously
    /// until quit() is called. It should return when the application is ready
    /// to terminate.
    ///
    /// Implementation notes:
    /// - Must process all pending events from the platform event queue
    /// - Should dispatch events to appropriate handlers (window, input, etc.)
    /// - Must handle user events posted via postUserEvent()
    /// - Should return gracefully when quit() is called
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
    /// Implementation notes:
    /// - Must check for pending events without blocking
    /// - Should process all available events before returning
    /// - Must handle user events posted via postUserEvent()
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
    /// Implementation notes:
    /// - Must use platform-specific low-power wait mechanisms
    /// - Should wake up when any event arrives (system or user)
    /// - macOS: Use CFRunLoop with infinite timeout
    /// - Windows: Use WaitMessage() or MsgWaitForMultipleObjects()
    ///
    /// - Throws: `LuminaError.eventLoopFailed` if wait fails
    mutating func wait() throws

    /// Post a user-defined event to the event queue (thread-safe).
    ///
    /// This method MUST be thread-safe, as it's the primary mechanism for
    /// background threads to communicate with the main event loop.
    ///
    /// Implementation notes:
    /// - Must use appropriate synchronization (locks, atomic operations)
    /// - Should wake up wait() if the event loop is sleeping
    /// - macOS: Use NSEvent.otherEvent and postEvent
    /// - Windows: Use PostMessage with custom WM_USER message
    ///
    /// - Parameter event: The user event to post
    nonisolated func postUserEvent(_ event: UserEvent)

    /// Request event loop termination.
    ///
    /// Signals the event loop to exit after processing current events.
    /// The run() method should return after this is called.
    ///
    /// Implementation notes:
    /// - Must be idempotent (safe to call multiple times)
    /// - Should complete current event processing before exiting
    /// - macOS: Set quit flag, optionally post sentinel event
    /// - Windows: Call PostQuitMessage(0)
    func quit()
}
