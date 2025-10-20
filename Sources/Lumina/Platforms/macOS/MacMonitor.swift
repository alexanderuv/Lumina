#if os(macOS)
import AppKit
import Foundation

/// macOS implementation of monitor enumeration using NSScreen.
///
/// This implementation uses NSScreen to enumerate all connected displays
/// and extract their properties including position, size, and scale factor.
internal struct MacMonitor {
    /// Enumerate all monitors in the system.
    ///
    /// - Returns: Array of all detected monitors
    /// - Throws: LuminaError if enumeration fails
    static func enumerateMonitors() throws -> [Monitor] {
        let screens = NSScreen.screens

        guard !screens.isEmpty else {
            throw LuminaError.platformError(
                platform: "macOS",
                operation: "Monitor enumeration",
                code: 0,
                message: "No monitors detected"
            )
        }

        var monitors: [Monitor] = []

        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            let visibleFrame = screen.visibleFrame  // Excludes menu bar, dock, etc.
            let scaleFactor = Float(screen.backingScaleFactor)

            // Convert from AppKit coordinates (bottom-left origin) to logical coordinates
            let physicalWidth = Int(frame.size.width * CGFloat(scaleFactor))
            let physicalHeight = Int(frame.size.height * CGFloat(scaleFactor))
            let physicalX = Int(frame.origin.x * CGFloat(scaleFactor))
            let physicalY = Int(frame.origin.y * CGFloat(scaleFactor))

            let physicalSize = PhysicalSize(width: physicalWidth, height: physicalHeight)
            let physicalPosition = PhysicalPosition(x: physicalX, y: physicalY)
            let logicalSize = physicalSize.toLogical(scaleFactor: scaleFactor)
            let logicalPosition = physicalPosition.toLogical(scaleFactor: scaleFactor)

            // Calculate work area (visible frame) in logical coordinates
            let workAreaLogicalX = Float(visibleFrame.origin.x)
            let workAreaLogicalY = Float(visibleFrame.origin.y)
            let workAreaLogicalWidth = Float(visibleFrame.size.width)
            let workAreaLogicalHeight = Float(visibleFrame.size.height)

            let workArea = LogicalRect(
                origin: LogicalPosition(x: workAreaLogicalX, y: workAreaLogicalY),
                size: LogicalSize(width: workAreaLogicalWidth, height: workAreaLogicalHeight)
            )

            // The first screen in NSScreen.screens is the primary monitor
            let isPrimary = (index == 0)

            // Get monitor name from localized description
            let name = screen.localizedName

            // Generate a unique ID based on screen pointer address
            let monitorID = MonitorID(UInt64(UInt(bitPattern: ObjectIdentifier(screen))))

            let monitor = Monitor(
                id: monitorID,
                name: name,
                position: logicalPosition,
                size: logicalSize,
                workArea: workArea,
                scaleFactor: scaleFactor,
                isPrimary: isPrimary
            )

            monitors.append(monitor)
        }

        return monitors
    }

    /// Get the primary monitor.
    ///
    /// - Returns: The primary monitor
    /// - Throws: LuminaError if no primary monitor is found
    static func primaryMonitor() throws -> Monitor {
        let monitors = try enumerateMonitors()
        guard let primary = monitors.first(where: { $0.isPrimary }) else {
            // Fallback to first monitor if no primary flag is set
            if let first = monitors.first {
                return first
            }
            throw LuminaError.platformError(
                platform: "macOS",
                operation: "Get primary monitor",
                code: 0,
                message: "No primary monitor found"
            )
        }
        return primary
    }
}

#endif
