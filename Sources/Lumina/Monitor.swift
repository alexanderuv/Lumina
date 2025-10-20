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
    public static func all() throws -> [Monitor] {
        #if os(Windows)
        return try WinMonitor.enumerateMonitors()
        #elseif os(macOS)
        return try MacMonitor.enumerateMonitors()
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
    public static func primary() throws -> Monitor {
        #if os(Windows)
        return try WinMonitor.primaryMonitor()
        #elseif os(macOS)
        return try MacMonitor.primaryMonitor()
        #else
        throw LuminaError.platformNotSupported(operation: "Monitor detection")
        #endif
    }
}
