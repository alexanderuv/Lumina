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
    /// - Monitor enumeration failures
    ///
    /// - Parameters:
    ///   - platform: The platform where the error occurred (e.g., "Windows", "macOS")
    ///   - operation: The operation that failed (e.g., "EnumDisplayMonitors")
    ///   - code: Platform-specific error code (e.g., NSError code, Win32 GetLastError)
    ///   - message: Optional human-readable error description
    case platformError(platform: String, operation: String, code: Int, message: String? = nil)

    /// The requested operation is not supported on this platform.
    ///
    /// This error occurs when attempting to use a feature that hasn't been
    /// implemented for the current platform.
    ///
    /// - Parameter operation: The operation that is not supported
    case platformNotSupported(operation: String)

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

    /// Clipboard access was denied by the system.
    ///
    /// This error occurs when the application attempts to read or write clipboard
    /// data but the operating system denies permission. This can happen due to:
    /// - Sandbox restrictions
    /// - Security policies
    /// - Clipboard locked by another application
    case clipboardAccessDenied

    /// Reading from the clipboard failed.
    ///
    /// This error occurs when clipboard read operations fail for reasons other
    /// than access denial. Common causes include:
    /// - Clipboard data corruption
    /// - Unsupported data format
    /// - Platform-specific clipboard errors
    ///
    /// - Parameter reason: Description of why the read failed
    case clipboardReadFailed(reason: String)

    /// Writing to the clipboard failed.
    ///
    /// This error occurs when clipboard write operations fail for reasons other
    /// than access denial. Common causes include:
    /// - Insufficient memory to allocate clipboard data
    /// - Platform-specific clipboard errors
    /// - Clipboard system unavailable
    ///
    /// - Parameter reason: Description of why the write failed
    case clipboardWriteFailed(reason: String)

    /// Monitor enumeration failed.
    ///
    /// This error occurs when the system cannot enumerate connected monitors.
    /// Common causes include:
    /// - Display server connection issues (Linux X11/Wayland)
    /// - Corrupted display configuration
    /// - Platform-specific monitor query failures
    ///
    /// - Parameter reason: Description of why enumeration failed
    case monitorEnumerationFailed(reason: String)

    /// The requested feature is not supported on this platform.
    ///
    /// This error occurs when attempting to use a platform-specific feature
    /// that is unavailable on the current platform. Unlike `platformNotSupported`,
    /// this indicates the feature exists but is platform-dependent.
    ///
    /// Examples:
    /// - X11 transparency (requires ARGB visual, rarely available)
    /// - Wayland always-on-top (no standard protocol)
    /// - Linux window decoration toggle on specific compositors
    ///
    /// Use capability queries to avoid this error:
    /// ```swift
    /// let caps = window.capabilities()
    /// if caps.supportsTransparency {
    ///     try window.setTransparent(true)
    /// } else {
    ///     // Feature unavailable, use fallback
    /// }
    /// ```
    ///
    /// - Parameter feature: The feature name (e.g., "transparency", "always-on-top")
    case unsupportedPlatformFeature(feature: String)

    /// Required Wayland protocol is missing.
    ///
    /// This error occurs on Linux Wayland systems when a required protocol
    /// is not advertised by the compositor. Essential protocols like xdg-shell
    /// are required for basic windowing functionality.
    ///
    /// Common causes:
    /// - Compositor is too old (missing protocol version)
    /// - Non-standard compositor implementation
    /// - Compositor bug or misconfiguration
    ///
    /// - Parameter protocol: The missing protocol name (e.g., "xdg-shell", "xdg-decoration")
    case waylandProtocolMissing(protocol: String)

    /// Required X11 extension is missing.
    ///
    /// This error occurs on Linux X11 systems when a required X11 extension
    /// is not available. Some extensions are critical for proper DPI handling
    /// or input event processing.
    ///
    /// Common causes:
    /// - X server is too old
    /// - Extension not compiled into X server
    /// - Extension disabled in X server configuration
    ///
    /// - Parameter extension: The missing extension name (e.g., "RANDR", "XInput2")
    case x11ExtensionMissing(extension: String)
}

extension LuminaError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .windowCreationFailed(let reason):
            return "Window creation failed: \(reason)"
        case .platformError(let platform, let operation, let code, let message):
            if let message = message {
                return "\(platform) error in \(operation) [\(code)]: \(message)"
            } else {
                return "\(platform) error in \(operation) [\(code)]"
            }
        case .platformNotSupported(let operation):
            return "Operation not supported on this platform: \(operation)"
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .eventLoopFailed(let reason):
            return "Event loop failed: \(reason)"
        case .clipboardAccessDenied:
            return "Clipboard access denied by the system"
        case .clipboardReadFailed(let reason):
            return "Clipboard read failed: \(reason)"
        case .clipboardWriteFailed(let reason):
            return "Clipboard write failed: \(reason)"
        case .monitorEnumerationFailed(let reason):
            return "Monitor enumeration failed: \(reason)"
        case .unsupportedPlatformFeature(let feature):
            return "Feature '\(feature)' is not supported on this platform"
        case .waylandProtocolMissing(let proto):
            return "Required Wayland protocol '\(proto)' is missing"
        case .x11ExtensionMissing(let ext):
            return "Required X11 extension '\(ext)' is missing"
        }
    }
}
