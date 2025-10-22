/// Monitor/display information and enumeration.
///
/// Provides cross-platform access to monitor information including
/// physical dimensions, position, DPI scaling, and primary monitor detection.

/// Unique identifier for a monitor.
public struct MonitorID: Sendable, Hashable, CustomStringConvertible {
    internal let value: UInt64

    internal init(_ value: UInt64) {
        self.value = value
    }

    public var description: String {
        "MonitorID(\(value))"
    }
}

/// Information about a physical monitor/display.
///
/// Monitors are detected at runtime and provide information about their
/// physical characteristics, position in the desktop coordinate space,
/// and DPI scaling factor.
///
/// Example:
/// ```swift
/// let monitors = try Monitor.all()
/// for monitor in monitors {
///     print("Monitor: \(monitor.name)")
///     print("  Position: \(monitor.position)")
///     print("  Size: \(monitor.size)")
///     print("  Work Area: \(monitor.workArea)")
///     print("  Scale: \(monitor.scaleFactor)x")
/// }
/// ```
public struct Monitor: Sendable, Hashable {
    /// Unique identifier for this monitor
    public let id: MonitorID

    /// Human-readable name of the monitor (e.g., "Generic PnP Monitor", "Dell U2415")
    public let name: String

    /// Position of the monitor in the virtual desktop coordinate space (logical coordinates)
    public let position: LogicalPosition

    /// Size of the monitor's display area (logical coordinates)
    public let size: LogicalSize

    /// Usable work area excluding system UI (menu bars, taskbars, docks, etc.) in logical coordinates
    ///
    /// The work area represents the portion of the monitor where applications can place windows.
    /// This excludes areas occupied by the operating system's UI elements like:
    /// - macOS: Menu bar at top, Dock on sides
    /// - Windows: Taskbar (usually at bottom)
    /// - Linux: Panel bars (varies by desktop environment)
    ///
    /// Example:
    /// ```swift
    /// let monitor = try Monitor.primary()
    /// print("Full size: \(monitor.size.width)×\(monitor.size.height)")
    /// print("Work area: \(monitor.workArea.size.width)×\(monitor.workArea.size.height)")
    /// ```
    public let workArea: LogicalRect

    /// DPI scale factor (1.0 = 96 DPI, 1.5 = 144 DPI, 2.0 = 192 DPI, etc.)
    public let scaleFactor: Float

    /// Whether this is the primary monitor
    public let isPrimary: Bool

    /// Physical size in pixels (convenience computed property)
    public var physicalSize: PhysicalSize {
        size.toPhysical(scaleFactor: scaleFactor)
    }

    /// Physical position in pixels (convenience computed property)
    public var physicalPosition: PhysicalPosition {
        position.toPhysical(scaleFactor: scaleFactor)
    }

    /// Enumerate all available monitors.
    ///
    /// - Returns: Array of all detected monitors
    /// - Throws: LuminaError if monitor enumeration fails
    ///
    /// Example:
    /// ```swift
    /// let monitors = try Monitor.all()
    /// print("Found \(monitors.count) monitor(s)")
    /// ```
    @MainActor
    public static func all() throws -> [Monitor] {
        #if os(Windows)
        return try WinMonitor.enumerateMonitors()
        #elseif os(macOS)
        return try MacMonitor.enumerateMonitors()
        #elseif os(Linux)
        throw LuminaError.invalidState("""
            Monitor.all() is not supported on Linux with the new platform/app separation API.

            Please use the platform instance method instead:

                let platform = try createLuminaPlatform()
                let monitors = try platform.enumerateMonitors()

            This architectural change provides proper resource lifetime management.
            """)
        #else
        throw LuminaError.platformNotSupported(operation: "Monitor enumeration")
        #endif
    }

    /// Get the primary monitor.
    ///
    /// - Returns: The primary monitor
    /// - Throws: LuminaError if no primary monitor is found
    ///
    /// Example:
    /// ```swift
    /// let primary = try Monitor.primary()
    /// print("Primary monitor: \(primary.name)")
    /// ```
    @MainActor
    public static func primary() throws -> Monitor {
        #if os(Windows)
        return try WinMonitor.primaryMonitor()
        #elseif os(macOS)
        return try MacMonitor.primaryMonitor()
        #elseif os(Linux)
        throw LuminaError.invalidState("""
            Monitor.primary() is not supported on Linux with the new platform/app separation API.

            Please use the platform instance method instead:

                let platform = try createLuminaPlatform()
                let primary = try platform.primaryMonitor()

            This architectural change provides proper resource lifetime management.
            """)
        #else
        throw LuminaError.platformNotSupported(operation: "Monitor detection")
        #endif
    }
}

// MARK: - Global Monitor Functions

/// Enumerate all available monitors.
///
/// This is a convenience function equivalent to `Monitor.all()`.
///
/// - Returns: Array of all detected monitors
/// - Throws: LuminaError if monitor enumeration fails
///
/// Example:
/// ```swift
/// let monitors = try enumerateMonitors()
/// for monitor in monitors {
///     print("Monitor: \(monitor.name) at \(monitor.position)")
/// }
/// ```
@MainActor
public func enumerateMonitors() throws -> [Monitor] {
    try Monitor.all()
}

/// Get the primary monitor.
///
/// This is a convenience function equivalent to `Monitor.primary()`.
///
/// - Returns: The primary monitor
/// - Throws: LuminaError if no primary monitor is found
///
/// Example:
/// ```swift
/// let primary = try primaryMonitor()
/// print("Primary monitor: \(primary.name), \(primary.size.width)×\(primary.size.height)")
/// ```
@MainActor
public func primaryMonitor() throws -> Monitor {
    try Monitor.primary()
}
