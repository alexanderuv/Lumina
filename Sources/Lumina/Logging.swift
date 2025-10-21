/// Logging infrastructure for Lumina framework.
///
/// Provides structured, high-resolution logging capabilities for debugging
/// and performance analysis. The logging system is designed for strict
/// concurrency compliance and supports multiple log levels for granular control.

import Foundation
import Logging

/// Configurable log levels for Lumina framework.
///
/// Log levels control the verbosity of logging output. Higher levels include
/// all messages from lower levels (e.g., `.debug` includes `.info`, `.error`).
///
/// Example:
/// ```swift
/// // Configure logging at application startup
/// LogLevel.current = .debug
///
/// let logger = LuminaLogger(label: "com.example.app")
/// logger.logEvent("Application started")  // Will be logged
/// logger.logTrace("Trace message")        // Will NOT be logged (trace > debug)
/// ```
public enum LogLevel: Int, Sendable, Comparable {
    /// No logging output
    case off = 0

    /// Only critical errors
    case error = 1

    /// Informational messages and errors
    case info = 2

    /// Debug messages, info, and errors
    case debug = 3

    /// All messages including trace-level details
    case trace = 4

    /// Current global log level (default: .info)
    ///
    /// This property controls the minimum log level for all LuminaLogger instances.
    /// Messages below this level will be filtered out.
    ///
    /// Thread-safe access is guaranteed through atomic operations.
    ///
    /// Example:
    /// ```swift
    /// LogLevel.current = .debug  // Enable debug logging
    /// LogLevel.current = .off    // Disable all logging
    /// ```
    @MainActor
    public static var current: LogLevel = .info

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Convert to swift-log Logger.Level
    internal var swiftLogLevel: Logger.Level {
        switch self {
        case .off:
            return .critical  // No direct "off" in swift-log, use highest level
        case .error:
            return .error
        case .info:
            return .info
        case .debug:
            return .debug
        case .trace:
            return .trace
        }
    }
}

/// High-resolution logger for Lumina framework.
///
/// LuminaLogger wraps apple/swift-log's Logger with Lumina-specific conveniences
/// and high-resolution timestamps for performance analysis. All logging operations
/// are thread-safe and Sendable-compliant.
///
/// The logger provides specialized methods for common logging patterns in Lumina:
/// - Event logging (window, input, monitor events)
/// - State transition tracking (event loop modes, window lifecycle)
/// - Platform-specific call logging (XCB, Wayland, AppKit operations)
/// - Capability detection logging (feature availability)
/// - Error logging with context
///
/// Example:
/// ```swift
/// let logger = LuminaLogger(label: "com.example.app.window")
///
/// // Log different event types
/// logger.logEvent("Window created with ID: \(windowID)")
/// logger.logStateTransition("Event loop mode changed: wait -> poll")
/// logger.logPlatformCall("xcb_create_window()", duration: 0.002)
/// logger.logError("Failed to enumerate monitors", error: error)
/// ```
public struct LuminaLogger: Sendable {
    /// Underlying swift-log Logger instance
    private let logger: Logger

    /// Configured log level for this logger instance
    private let configuredLevel: LogLevel

    /// Create a logger with a specific label.
    ///
    /// The label typically identifies the subsystem or component creating the log.
    /// Use reverse-DNS notation for consistency (e.g., "com.example.app.window").
    ///
    /// The logger captures the current global log level at initialization time.
    /// This ensures thread-safe operation without requiring @MainActor isolation.
    ///
    /// - Parameters:
    ///   - label: Identifying label for this logger
    ///   - level: Optional explicit log level (defaults to LogLevel.current if created on MainActor)
    ///
    /// Example:
    /// ```swift
    /// // On MainActor - uses global level
    /// let appLogger = LuminaLogger(label: "com.example.app")
    ///
    /// // Explicit level - works from any thread
    /// let windowLogger = LuminaLogger(label: "com.example.app.window", level: .debug)
    /// ```
    public init(label: String, level: LogLevel? = nil) {
        var logger = Logger(label: label)

        // Use explicit level if provided, otherwise use .info as default
        let logLevel = level ?? .info
        self.configuredLevel = logLevel
        logger.logLevel = logLevel.swiftLogLevel

        self.logger = logger
    }

    /// Create a logger on MainActor using the global log level.
    ///
    /// This initializer captures the current global log level setting.
    /// Use this when creating loggers from MainActor-isolated code.
    ///
    /// - Parameter label: Identifying label for this logger
    /// - Returns: Logger configured with current global level
    ///
    /// Example:
    /// ```swift
    /// @MainActor
    /// func setup() {
    ///     LogLevel.current = .debug
    ///     let logger = LuminaLogger.makeLogger(label: "com.example.app")
    ///     // Logger will use .debug level
    /// }
    /// ```
    @MainActor
    public static func makeLogger(label: String) -> LuminaLogger {
        LuminaLogger(label: label, level: LogLevel.current)
    }

    // MARK: - Convenience Logging Methods

    /// Log an event occurrence.
    ///
    /// Use this for general event logging (window creation, input events, etc.).
    /// Events are logged at `.info` level with high-resolution timestamps.
    ///
    /// - Parameter message: Description of the event
    ///
    /// Example:
    /// ```swift
    /// logger.logEvent("Window \(windowID) resized to \(size)")
    /// logger.logEvent("Monitor configuration changed: \(monitors.count) monitors")
    /// ```
    public func logEvent(_ message: String) {
        guard configuredLevel >= .info else { return }
        let timestamp = HighResolutionTimestamp.now()
        logger.info("\(timestamp) [EVENT] \(message)")
    }

    /// Log a state transition.
    ///
    /// Use this for logging state changes in the application lifecycle or event loop.
    /// State transitions are logged at `.info` level with high-resolution timestamps.
    ///
    /// - Parameter message: Description of the state transition
    ///
    /// Example:
    /// ```swift
    /// logger.logStateTransition("Event loop mode: wait -> poll")
    /// logger.logStateTransition("Window state: hidden -> visible")
    /// logger.logStateTransition("Focus changed: window A -> window B")
    /// ```
    public func logStateTransition(_ message: String) {
        guard configuredLevel >= .info else { return }
        let timestamp = HighResolutionTimestamp.now()
        logger.info("\(timestamp) [STATE] \(message)")
    }

    /// Log a platform-specific API call.
    ///
    /// Use this for logging low-level platform operations (XCB calls, Wayland protocol
    /// messages, AppKit method calls). Platform calls are logged at `.debug` level
    /// with high-resolution timestamps and optional duration.
    ///
    /// - Parameters:
    ///   - call: Description of the platform call
    ///   - duration: Optional duration in seconds (for performance analysis)
    ///
    /// Example:
    /// ```swift
    /// logger.logPlatformCall("xcb_create_window()")
    /// logger.logPlatformCall("NSWindow.setFrame(_:display:)", duration: 0.0015)
    /// logger.logPlatformCall("wl_surface_commit()", duration: 0.0008)
    /// ```
    public func logPlatformCall(_ call: String, duration: TimeInterval? = nil) {
        guard configuredLevel >= .debug else { return }
        let timestamp = HighResolutionTimestamp.now()
        if let duration = duration {
            logger.debug("\(timestamp) [PLATFORM] \(call) (\(String(format: "%.3fms", duration * 1000)))")
        } else {
            logger.debug("\(timestamp) [PLATFORM] \(call)")
        }
    }

    /// Log capability detection results.
    ///
    /// Use this for logging platform capability queries and feature availability.
    /// Capability detection is logged at `.debug` level with high-resolution timestamps.
    ///
    /// - Parameter message: Description of the capability detection
    ///
    /// Example:
    /// ```swift
    /// logger.logCapabilityDetection("X11 RANDR extension: available (v1.5)")
    /// logger.logCapabilityDetection("Wayland xdg-decoration protocol: missing")
    /// logger.logCapabilityDetection("Window transparency: supported")
    /// ```
    public func logCapabilityDetection(_ message: String) {
        guard configuredLevel >= .debug else { return }
        let timestamp = HighResolutionTimestamp.now()
        logger.debug("\(timestamp) [CAPABILITY] \(message)")
    }

    /// Log an error condition.
    ///
    /// Use this for logging errors and exceptional conditions. Errors are logged
    /// at `.error` level with high-resolution timestamps and full error details.
    ///
    /// - Parameters:
    ///   - message: Description of the error context
    ///   - error: Optional error instance for detailed error information
    ///
    /// Example:
    /// ```swift
    /// logger.logError("Failed to create window")
    /// logger.logError("Monitor enumeration failed", error: error)
    /// logger.logError("Clipboard read failed", error: LuminaError.clipboardAccessDenied)
    /// ```
    public func logError(_ message: String, error: Error? = nil) {
        guard configuredLevel >= .error else { return }
        let timestamp = HighResolutionTimestamp.now()
        if let error = error {
            logger.error("\(timestamp) [ERROR] \(message): \(String(describing: error))")
        } else {
            logger.error("\(timestamp) [ERROR] \(message)")
        }
    }

    // MARK: - Raw Logging Methods

    /// Log a trace-level message.
    ///
    /// Trace logging provides extremely detailed information for deep debugging.
    /// Use sparingly as it can generate large amounts of output.
    ///
    /// - Parameter message: The message to log
    ///
    /// Example:
    /// ```swift
    /// logger.logTrace("Entering event pump loop iteration \(iteration)")
    /// logger.logTrace("XCB event queue: \(queueSize) pending events")
    /// ```
    public func logTrace(_ message: String) {
        guard configuredLevel >= .trace else { return }
        let timestamp = HighResolutionTimestamp.now()
        logger.trace("\(timestamp) \(message)")
    }

    /// Log a debug-level message.
    ///
    /// Debug logging provides detailed information for troubleshooting.
    /// This is the recommended level for development.
    ///
    /// - Parameter message: The message to log
    ///
    /// Example:
    /// ```swift
    /// logger.logDebug("Processing \(eventCount) events")
    /// logger.logDebug("Window registry size: \(windows.count)")
    /// ```
    public func logDebug(_ message: String) {
        guard configuredLevel >= .debug else { return }
        let timestamp = HighResolutionTimestamp.now()
        logger.debug("\(timestamp) \(message)")
    }

    /// Log an info-level message.
    ///
    /// Info logging provides high-level information about application flow.
    /// This is the default logging level.
    ///
    /// - Parameter message: The message to log
    ///
    /// Example:
    /// ```swift
    /// logger.logInfo("Application started")
    /// logger.logInfo("Event loop mode changed to poll")
    /// ```
    public func logInfo(_ message: String) {
        guard configuredLevel >= .info else { return }
        let timestamp = HighResolutionTimestamp.now()
        logger.info("\(timestamp) \(message)")
    }
}

// MARK: - High-Resolution Timestamps

/// High-resolution timestamp for performance analysis.
///
/// Provides microsecond-precision timestamps using mach_absolute_time (macOS)
/// or CLOCK_MONOTONIC (Linux). Timestamps are monotonic and not affected by
/// system clock changes.
///
/// Conforms to Sendable for safe cross-thread timestamp passing.
///
/// Example:
/// ```swift
/// let timestamp = HighResolutionTimestamp.now()
/// print("Event occurred at: \(timestamp)")  // Prints formatted timestamp
/// ```
internal struct HighResolutionTimestamp: Sendable, CustomStringConvertible {
    /// Time in seconds since an arbitrary reference point (monotonic)
    private let seconds: Double

    /// Create a timestamp at the current time.
    ///
    /// Uses high-resolution monotonic clocks:
    /// - macOS: mach_absolute_time with timebase conversion
    /// - Linux: clock_gettime(CLOCK_MONOTONIC_RAW)
    /// - Other platforms: Date.timeIntervalSinceReferenceDate (fallback)
    ///
    /// - Returns: Current high-resolution timestamp
    static func now() -> HighResolutionTimestamp {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanoseconds = mach_absolute_time() * UInt64(info.numer) / UInt64(info.denom)
        let seconds = Double(nanoseconds) / 1_000_000_000.0
        return HighResolutionTimestamp(seconds: seconds)
        #elseif os(Linux)
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
        let seconds = Double(ts.tv_sec) + Double(ts.tv_nsec) / 1_000_000_000.0
        return HighResolutionTimestamp(seconds: seconds)
        #else
        // Fallback to Date for other platforms
        return HighResolutionTimestamp(seconds: Date.timeIntervalSinceReferenceDate)
        #endif
    }

    /// Initialize with a specific time value.
    ///
    /// - Parameter seconds: Time in seconds since arbitrary reference
    private init(seconds: Double) {
        self.seconds = seconds
    }

    /// Formatted timestamp string with microsecond precision.
    ///
    /// Format: `[SSSSSSSSSS.UUUUUU]` where S = seconds, U = microseconds
    ///
    /// Example output: `[1234567.890123]`
    public var description: String {
        String(format: "[%.6f]", seconds)
    }
}

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin

// mach_absolute_time is available from Darwin
#elseif os(Linux)
import Glibc

// clock_gettime is available from Glibc
#endif
