/// Geometry types for window sizing and positioning.
///
/// Lumina distinguishes between logical (device-independent) and physical (pixel-based)
/// coordinates to ensure proper DPI/scaling handling across platforms.

/// Logical (device-independent) size in points.
///
/// Logical sizes represent platform-independent measurements that automatically
/// scale based on the display's DPI/scale factor. On a Retina display (2x scale),
/// a logical size of 800×600 translates to 1600×1200 physical pixels.
///
/// Use logical sizes for all window sizing operations to ensure consistent
/// appearance across different displays.
///
/// Example:
/// ```swift
/// let windowSize = LogicalSize(width: 800, height: 600)
/// let scaleFactor = window.scaleFactor()
/// let physicalSize = windowSize.toPhysical(scaleFactor: scaleFactor)
/// print("Physical pixels: \(physicalSize.width)×\(physicalSize.height)")
/// ```
public struct LogicalSize: Sendable, Hashable {
    /// Width in logical points
    public let width: Float

    /// Height in logical points
    public let height: Float

    /// Create a logical size.
    ///
    /// - Parameters:
    ///   - width: Width in logical points
    ///   - height: Height in logical points
    public init(width: Float, height: Float) {
        self.width = width
        self.height = height
    }

    /// Convert to physical pixels using the given scale factor.
    ///
    /// - Parameter scaleFactor: The display scale factor (e.g., 2.0 for Retina)
    /// - Returns: Physical size in pixels
    ///
    /// Example:
    /// ```swift
    /// let logical = LogicalSize(width: 800, height: 600)
    /// let physical = logical.toPhysical(scaleFactor: 2.0)
    /// // physical.width == 1600, physical.height == 1200
    /// ```
    public func toPhysical(scaleFactor: Float) -> PhysicalSize {
        PhysicalSize(
            width: Int((width * scaleFactor).rounded()),
            height: Int((height * scaleFactor).rounded())
        )
    }
}

/// Physical (pixel-based) size.
///
/// Physical sizes represent actual pixel dimensions on the display.
/// These values change based on the display's DPI/scale factor.
///
/// Most APIs should use LogicalSize instead. PhysicalSize is primarily
/// used for low-level rendering operations or when querying actual
/// pixel dimensions.
///
/// Example:
/// ```swift
/// let physicalSize = PhysicalSize(width: 1920, height: 1080)
/// let logicalSize = physicalSize.toLogical(scaleFactor: 2.0)
/// // logicalSize.width == 960, logicalSize.height == 540
/// ```
public struct PhysicalSize: Sendable, Hashable {
    /// Width in physical pixels
    public let width: Int

    /// Height in physical pixels
    public let height: Int

    /// Create a physical size.
    ///
    /// - Parameters:
    ///   - width: Width in physical pixels
    ///   - height: Height in physical pixels
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Convert to logical points using the given scale factor.
    ///
    /// - Parameter scaleFactor: The display scale factor (e.g., 2.0 for Retina)
    /// - Returns: Logical size in points
    ///
    /// Example:
    /// ```swift
    /// let physical = PhysicalSize(width: 1600, height: 1200)
    /// let logical = physical.toLogical(scaleFactor: 2.0)
    /// // logical.width == 800, logical.height == 600
    /// ```
    public func toLogical(scaleFactor: Float) -> LogicalSize {
        LogicalSize(
            width: Float(width) / scaleFactor,
            height: Float(height) / scaleFactor
        )
    }
}

/// Logical (device-independent) position in screen coordinates.
///
/// Logical positions use the same coordinate system as LogicalSize,
/// automatically scaling based on the display's DPI/scale factor.
///
/// Coordinate system: Origin (0, 0) is at the top-left corner of the screen.
/// X increases to the right, Y increases downward (normalized across platforms).
///
/// Example:
/// ```swift
/// let position = LogicalPosition(x: 100, y: 200)
/// window.moveTo(position)
/// ```
public struct LogicalPosition: Sendable, Hashable {
    /// X coordinate in logical points
    public let x: Float

    /// Y coordinate in logical points
    public let y: Float

    /// Create a logical position.
    ///
    /// - Parameters:
    ///   - x: X coordinate in logical points (0 = left edge)
    ///   - y: Y coordinate in logical points (0 = top edge)
    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    /// Convert to physical pixels using the given scale factor.
    ///
    /// - Parameter scaleFactor: The display scale factor (e.g., 2.0 for Retina)
    /// - Returns: Physical position in pixels
    ///
    /// Example:
    /// ```swift
    /// let logical = LogicalPosition(x: 100, y: 200)
    /// let physical = logical.toPhysical(scaleFactor: 2.0)
    /// // physical.x == 200, physical.y == 400
    /// ```
    public func toPhysical(scaleFactor: Float) -> PhysicalPosition {
        PhysicalPosition(
            x: Int((x * scaleFactor).rounded()),
            y: Int((y * scaleFactor).rounded())
        )
    }
}

/// Physical (pixel-based) position in screen coordinates.
///
/// Physical positions represent actual pixel coordinates on the display.
/// These values change based on the display's DPI/scale factor.
///
/// Most APIs should use LogicalPosition instead. PhysicalPosition is primarily
/// used for low-level operations or when querying actual pixel coordinates.
///
/// Coordinate system: Origin (0, 0) is at the top-left corner of the screen.
/// X increases to the right, Y increases downward.
///
/// Example:
/// ```swift
/// let physical = PhysicalPosition(x: 200, y: 400)
/// let logical = physical.toLogical(scaleFactor: 2.0)
/// // logical.x == 100, logical.y == 200
/// ```
public struct PhysicalPosition: Sendable, Hashable {
    /// X coordinate in physical pixels
    public let x: Int

    /// Y coordinate in physical pixels
    public let y: Int

    /// Create a physical position.
    ///
    /// - Parameters:
    ///   - x: X coordinate in physical pixels (0 = left edge)
    ///   - y: Y coordinate in physical pixels (0 = top edge)
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// Convert to logical points using the given scale factor.
    ///
    /// - Parameter scaleFactor: The display scale factor (e.g., 2.0 for Retina)
    /// - Returns: Logical position in points
    ///
    /// Example:
    /// ```swift
    /// let physical = PhysicalPosition(x: 200, y: 400)
    /// let logical = physical.toLogical(scaleFactor: 2.0)
    /// // logical.x == 100, logical.y == 200
    /// ```
    public func toLogical(scaleFactor: Float) -> LogicalPosition {
        LogicalPosition(
            x: Float(x) / scaleFactor,
            y: Float(y) / scaleFactor
        )
    }
}
