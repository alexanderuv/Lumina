/// Control flow modes for event loop execution.
///
/// Control flow modes determine how the event loop waits for or retrieves events.
/// These modes provide fine-grained control over event processing behavior, enabling
/// efficient event handling for different application patterns (games, UI apps, background tasks).

import Foundation

/// Control flow mode for event loop operation.
///
/// The control flow mode specifies how `pumpEvents(mode:)` should wait for events.
/// Different modes enable different application patterns:
/// - `.wait`: Efficient for UI applications that react to user input
/// - `.poll`: Efficient for games or simulations with continuous rendering
/// - `.waitUntil`: Efficient for animations with frame pacing
///
/// Example:
/// ```swift
/// // UI application: block until user input
/// while let event = app.pumpEvents(mode: .wait) {
///     handleEvent(event)
/// }
///
/// // Game loop: poll events, then render
/// loop {
///     while let event = app.pumpEvents(mode: .poll) {
///         handleEvent(event)
///     }
///     render()
/// }
///
/// // Animation with frame pacing: wait up to 16ms for 60fps
/// let deadline = Deadline(seconds: 1.0 / 60.0)
/// while let event = app.pumpEvents(mode: .waitUntil(deadline)) {
///     handleEvent(event)
/// }
/// render()
/// ```
public enum ControlFlowMode: Sendable {
    /// Block until an event is available.
    ///
    /// The event loop will sleep until an event arrives, minimizing CPU usage.
    /// This is the most efficient mode for event-driven applications.
    ///
    /// Use this mode when your application only needs to respond to user input
    /// or system events, with no continuous rendering or background work.
    case wait

    /// Return immediately with available events (non-blocking).
    ///
    /// The event loop will process all pending events and return immediately,
    /// even if no events are available. This mode never blocks.
    ///
    /// Use this mode when your application needs to continuously render or
    /// perform background work between event processing.
    case poll

    /// Block until an event is available or the deadline expires.
    ///
    /// The event loop will wait up to the specified deadline for events.
    /// If the deadline expires before an event arrives, the function returns nil.
    ///
    /// Use this mode for frame-paced rendering where you want to process events
    /// but also ensure frames are rendered at consistent intervals.
    ///
    /// - Parameter deadline: The deadline after which to stop waiting
    case waitUntil(Deadline)
}

/// A point in time used for timeouts in control flow modes.
///
/// Deadline represents a specific moment in time and can be checked to see if
/// it has already passed. Deadlines are used with `.waitUntil` control flow mode
/// to implement frame pacing and timed event processing.
///
/// Example:
/// ```swift
/// // Create a deadline 16.67ms from now (60 fps)
/// let deadline = Deadline(seconds: 1.0 / 60.0)
///
/// // Process events until deadline
/// while let event = app.pumpEvents(mode: .waitUntil(deadline)) {
///     handleEvent(event)
/// }
///
/// // Check if deadline has passed
/// if deadline.hasExpired {
///     print("Deadline expired, moving to next frame")
/// }
/// ```
public struct Deadline: Sendable {
    /// The target date/time for this deadline
    internal let date: Date

    /// Create a deadline relative to the current time.
    ///
    /// - Parameter seconds: Number of seconds from now until the deadline
    ///
    /// Example:
    /// ```swift
    /// let deadline = Deadline(seconds: 0.1)  // 100ms from now
    /// ```
    public init(seconds: TimeInterval) {
        self.date = Date(timeIntervalSinceNow: seconds)
    }

    /// Create a deadline at a specific date/time.
    ///
    /// - Parameter date: The target date/time for the deadline
    ///
    /// Example:
    /// ```swift
    /// let targetTime = Date().addingTimeInterval(5.0)  // 5 seconds from now
    /// let deadline = Deadline(date: targetTime)
    /// ```
    public init(date: Date) {
        self.date = date
    }

    /// Check if the deadline has passed.
    ///
    /// Returns true if the current time is past the deadline's target time.
    ///
    /// Example:
    /// ```swift
    /// let deadline = Deadline(seconds: 0.01)
    /// Thread.sleep(forTimeInterval: 0.02)
    /// if deadline.hasExpired {
    ///     print("Deadline has passed")
    /// }
    /// ```
    public var hasExpired: Bool {
        Date() >= date
    }

    /// Get the internal date for platform-specific event loop integration.
    ///
    /// This property is used internally by platform implementations to integrate
    /// with native event loops (NSRunLoop, select(), etc.).
    internal var internalDate: Date {
        date
    }
}
