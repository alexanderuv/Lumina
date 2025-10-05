/// Errors that can occur when using Lumina.
///
/// LuminaError provides explicit, typed error handling for all recoverable
/// error conditions. The error cases are designed to be actionable, providing
/// enough context to diagnose and handle failures appropriately.
///
/// Error handling patterns:
/// - Window creation failures return `Result<Window, LuminaError>` for explicit handling
/// - Event loop operations use `throws` for propagating critical failures
/// - All errors are Sendable for safe cross-thread error reporting
///
/// Example:
/// ```swift
/// // Handling window creation errors
/// let result = Window.create(title: "App", size: LogicalSize(width: 800, height: 600))
/// switch result {
/// case .success(let window):
///     window.show()
/// case .failure(.windowCreationFailed(let reason)):
///     print("Failed to create window: \(reason)")
///     // Attempt fallback or show error to user
/// case .failure(let error):
///     print("Unexpected error: \(error)")
/// }
///
/// // Handling event loop errors
/// do {
///     try app.run()
/// } catch let error as LuminaError {
///     switch error {
///     case .eventLoopFailed(let reason):
///         print("Event loop crashed: \(reason)")
///         // Log and restart or exit gracefully
///     default:
///         print("Unexpected error: \(error)")
///     }
/// }
/// ```
public enum LuminaError: Error, Sendable {
    /// Window creation or manipulation failed.
    ///
    /// This error occurs when the system cannot create a window due to
    /// resource constraints, invalid parameters, or platform limitations.
    ///
    /// Common causes:
    /// - Insufficient memory to allocate window resources
    /// - Invalid window size (negative or zero dimensions)
    /// - Platform-specific window creation failures
    ///
    /// - Parameter reason: Human-readable description of why creation failed
    case windowCreationFailed(reason: String)

    /// Platform-specific error occurred.
    ///
    /// This error wraps underlying operating system errors, providing both
    /// the native error code and a human-readable message.
    ///
    /// Common causes:
    /// - Graphics system initialization failures
    /// - DPI awareness configuration errors
    /// - Display connection issues
    ///
    /// - Parameters:
    ///   - code: Platform-specific error code (e.g., NSError code, Win32 GetLastError)
    ///   - message: Human-readable error description
    case platformError(code: Int, message: String)

    /// Invalid API usage or state.
    ///
    /// This error indicates a programming error, such as calling methods
    /// in the wrong order or passing invalid arguments.
    ///
    /// Common causes:
    /// - Operating on a closed window
    /// - Creating multiple Application instances
    /// - Invalid state transitions
    ///
    /// - Parameter message: Description of the invalid state or usage
    case invalidState(String)

    /// Event loop operation failed.
    ///
    /// This error occurs when the event loop encounters an unrecoverable
    /// error during event processing. This is typically a critical failure
    /// that requires application shutdown.
    ///
    /// Common causes:
    /// - Corrupted event queue
    /// - Platform event system failure
    /// - Thread synchronization errors
    ///
    /// - Parameter reason: Description of why the event loop failed
    case eventLoopFailed(reason: String)
}

extension LuminaError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .windowCreationFailed(let reason):
            return "Window creation failed: \(reason)"
        case .platformError(let code, let message):
            return "Platform error [\(code)]: \(message)"
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .eventLoopFailed(let reason):
            return "Event loop failed: \(reason)"
        }
    }
}
