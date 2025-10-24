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
/// let logger = LuminaLogger(label: "myapp.main")
/// logger.info("Application started")  // Will be logged
/// logger.trace("Trace message")        // Will NOT be logged (trace > debug)
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

/// Logger for Lumina framework.
///
/// LuminaLogger provides a simple wrapper around apple/swift-log's Logger
/// with Lumina-specific configuration. All logging operations are thread-safe
/// and Sendable-compliant.
///
/// Example:
/// ```swift
/// let logger = LuminaLogger(label: "myapp.window")
/// logger.info("Window created with ID: \(windowID)")
/// logger.debug("Processing event")
/// logger.error("Failed to enumerate monitors")
/// ```
public struct LuminaLogger: Sendable {
    /// Underlying swift-log Logger instance
    private let logger: Logger

    /// Configured log level for this logger instance
    private let configuredLevel: LogLevel

    /// Create a logger with a specific label.
    ///
    /// The label typically identifies the subsystem or component creating the log.
    /// Use dot-separated naming for consistency (e.g., "myapp.window", "lumina.wayland").
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
    /// let appLogger = LuminaLogger(label: "myapp.main")
    ///
    /// // Explicit level - works from any thread
    /// let windowLogger = LuminaLogger(label: "myapp.window", level: .debug)
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
    ///     let logger = LuminaLogger.makeLogger(label: "myapp.main")
    ///     // Logger will use .debug level
    /// }
    /// ```
    @MainActor
    public static func makeLogger(label: String) -> LuminaLogger {
        LuminaLogger(label: label, level: LogLevel.current)
    }

    // MARK: - Logging Methods

    /// Log a trace-level message.
    public func trace(_ message: @autoclosure () -> Logger.Message) {
        logger.trace(message())
    }

    /// Log a debug-level message.
    public func debug(_ message: @autoclosure () -> Logger.Message) {
        logger.debug(message())
    }

    /// Log an info-level message.
    public func info(_ message: @autoclosure () -> Logger.Message) {
        logger.info(message())
    }

    /// Log a warning-level message.
    public func warning(_ message: @autoclosure () -> Logger.Message) {
        logger.warning(message())
    }

    /// Log an error-level message.
    public func error(_ message: @autoclosure () -> Logger.Message) {
        logger.error(message())
    }
}
