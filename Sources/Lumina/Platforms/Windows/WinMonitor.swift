#if os(Windows)
import WinSDK
import Foundation

/// Windows implementation of monitor enumeration using Win32 API.
///
/// This implementation uses EnumDisplayMonitors to detect all monitors
/// and GetDpiForMonitor to query DPI information for each display.
internal struct WinMonitor {
    /// Context for monitor enumeration callback
    private final class EnumContext: @unchecked Sendable {
        var monitors: [Monitor] = []
        let lock = NSLock()

        func append(_ monitor: Monitor) {
            lock.lock()
            defer { lock.unlock() }
            monitors.append(monitor)
        }
    }

    /// Enumerate all monitors in the system.
    ///
    /// - Returns: Array of all detected monitors
    /// - Throws: LuminaError if enumeration fails
    static func enumerateMonitors() throws -> [Monitor] {
        let context = EnumContext()

        // EnumDisplayMonitors callback - must be a C function pointer
        let callback: MONITORENUMPROC = { (hMonitor, hdc, rect, lParam) -> WindowsBool in
            guard let hMonitor = hMonitor else {
                return true // Continue enumeration
            }

            // Extract context from lParam
            let context = Unmanaged<EnumContext>.fromOpaque(UnsafeRawPointer(bitPattern: Int(lParam))!).takeUnretainedValue()

            // Get monitor info - cast MONITORINFOEXW pointer to MONITORINFO pointer
            var monitorInfo = MONITORINFOEXW()
            monitorInfo.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)

            let success = withUnsafeMutablePointer(to: &monitorInfo) { ptr in
                ptr.withMemoryRebound(to: MONITORINFO.self, capacity: 1) { monitorInfoPtr in
                    GetMonitorInfoW(hMonitor, monitorInfoPtr)
                }
            }

            guard success else {
                return true // Continue enumeration even if this one fails
            }

            // Get DPI for this monitor
            var dpiX: UINT = 96
            var dpiY: UINT = 96
            let hr = GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
            guard hr >= 0 else {
                fatalError("GetDpiForMonitor failed with HRESULT: 0x\(String(hr, radix: 16))")
            }

            // Use the larger of the two DPI values (they should be the same on Windows)
            let dpi = max(dpiX, dpiY)
            let scaleFactor = Float(dpi) / 96.0

            // Extract monitor bounds (in physical pixels)
            let rcMonitor = monitorInfo.rcMonitor
            let physicalWidth = Int(rcMonitor.right - rcMonitor.left)
            let physicalHeight = Int(rcMonitor.bottom - rcMonitor.top)
            let physicalX = Int(rcMonitor.left)
            let physicalY = Int(rcMonitor.top)

            // Convert to logical coordinates
            let physicalSize = PhysicalSize(width: physicalWidth, height: physicalHeight)
            let physicalPosition = PhysicalPosition(x: physicalX, y: physicalY)
            let logicalSize = physicalSize.toLogical(scaleFactor: scaleFactor)
            let logicalPosition = physicalPosition.toLogical(scaleFactor: scaleFactor)

            // Check if this is the primary monitor
            let isPrimary = (monitorInfo.dwFlags & DWORD(MONITORINFOF_PRIMARY)) != 0

            // Extract device name from MONITORINFOEXW.szDevice
            let deviceName = withUnsafePointer(to: monitorInfo.szDevice) { ptr in
                ptr.withMemoryRebound(to: UInt16.self, capacity: Int(CCHDEVICENAME)) { wcharPtr in
                    String(decodingCString: wcharPtr, as: UTF16.self)
                }
            }

            // Generate a unique ID based on monitor handle
            let monitorID = MonitorID(UInt64(bitPattern: Int64(Int(bitPattern: hMonitor))))

            // Extract work area (screen minus taskbar)
            let rcWork = monitorInfo.rcWork
            let workAreaPhysicalPos = PhysicalPosition(x: Int(rcWork.left), y: Int(rcWork.top))
            let workAreaPhysicalSize = PhysicalSize(
                width: Int(rcWork.right - rcWork.left),
                height: Int(rcWork.bottom - rcWork.top)
            )
            let workAreaLogical = LogicalRect(
                origin: workAreaPhysicalPos.toLogical(scaleFactor: scaleFactor),
                size: workAreaPhysicalSize.toLogical(scaleFactor: scaleFactor)
            )

            let monitor = Monitor(
                id: monitorID,
                name: deviceName.isEmpty ? "Unknown Monitor" : deviceName,
                position: logicalPosition,
                size: logicalSize,
                workArea: workAreaLogical,
                scaleFactor: scaleFactor,
                isPrimary: isPrimary
            )

            context.append(monitor)
            return true // Continue enumeration
        }

        // Enumerate all monitors
        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        let result = EnumDisplayMonitors(nil, nil, callback, LPARAM(Int(bitPattern: contextPtr)))

        guard result else {
            throw LuminaError.platformError(
                platform: "Windows",
                operation: "EnumDisplayMonitors",
                code: Int(GetLastError())
            )
        }

        guard !context.monitors.isEmpty else {
            throw LuminaError.platformError(
                platform: "Windows",
                operation: "Monitor enumeration",
                code: 0,
                message: "No monitors detected"
            )
        }

        return context.monitors
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
                platform: "Windows",
                operation: "Get primary monitor",
                code: 0,
                message: "No primary monitor found"
            )
        }
        return primary
    }
}

#endif
