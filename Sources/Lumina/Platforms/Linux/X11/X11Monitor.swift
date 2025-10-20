#if os(Linux)
import CXCBLinux
import Foundation

/// X11 monitor enumeration using XRandR (X Resize and Rotate extension).
///
/// This module provides monitor detection and DPI scaling for X11 systems using
/// the XRandR extension. It handles:
/// - Monitor enumeration via xcb_randr_get_screen_resources_current
/// - Output info parsing (position, size, rotation, connection status)
/// - DPI detection with fallback hierarchy: XSETTINGS → Xft.dpi → physical dimensions → 96 DPI
/// - Monitor configuration change notifications (XCB_RANDR_SCREEN_CHANGE_NOTIFY)
/// - Primary monitor detection
///
/// XRandR is the standard X11 extension for monitor management and is supported by
/// all modern X servers (XOrg, Xephyr, etc.). It provides accurate monitor information
/// including physical size, EDID data, and dynamic configuration changes.
///
/// Example usage:
/// ```swift
/// let monitors = try X11Monitor.enumerateMonitors(connection: connection, screen: screen)
/// print("Found \(monitors.count) monitor(s)")
///
/// let primary = try X11Monitor.primaryMonitor(connection: connection, screen: screen)
/// print("Primary monitor: \(primary.name) at \(primary.position)")
/// ```
@MainActor
public enum X11Monitor {

    // MARK: - Monitor Enumeration

    /// Enumerate all connected monitors using XRandR.
    ///
    /// This function queries XRandR for all outputs (monitors) and filters to only
    /// include connected outputs with valid modes. Each monitor is converted to a
    /// Lumina Monitor struct with proper DPI scaling.
    ///
    /// The enumeration process:
    /// 1. Query XRandR screen resources (xcb_randr_get_screen_resources_current)
    /// 2. Iterate all outputs and query output info (xcb_randr_get_output_info)
    /// 3. Filter to connected outputs with valid CRTC (active)
    /// 4. Query CRTC info for position and current mode
    /// 5. Detect DPI and calculate scale factor
    /// 6. Build Monitor struct
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - screen: Default screen
    /// - Returns: Array of all connected monitors
    /// - Throws: LuminaError.monitorEnumerationFailed or LuminaError.x11ExtensionMissing
    ///
    /// Example:
    /// ```swift
    /// do {
    ///     let monitors = try X11Monitor.enumerateMonitors(connection: conn, screen: screen)
    ///     for monitor in monitors {
    ///         print("\(monitor.name): \(monitor.size.width)×\(monitor.size.height) @ \(monitor.scaleFactor)x")
    ///     }
    /// } catch {
    ///     print("Monitor enumeration failed: \(error)")
    /// }
    /// ```
    public static func enumerateMonitors(
        connection: OpaquePointer,
        screen: UnsafeMutablePointer<xcb_screen_t>
    ) throws -> [Monitor] {
        let rootWindow = screen.pointee.root

        // Query XRandR screen resources (current configuration)
        let resourcesCookie = xcb_randr_get_screen_resources_current(connection, rootWindow)
        var error: UnsafeMutablePointer<xcb_generic_error_t>?
        guard let resourcesReply = xcb_randr_get_screen_resources_current_reply(connection, resourcesCookie, &error) else {
            if let error = error {
                let errorCode = Int(error.pointee.error_code)
                free(error)
                throw LuminaError.x11ExtensionMissing(extension: "XRandR (error code: \(errorCode))")
            }
            throw LuminaError.x11ExtensionMissing(extension: "XRandR (unknown error)")
        }
        defer { free(resourcesReply) }

        // Get outputs array from reply
        let outputCount = Int(xcb_randr_get_screen_resources_current_outputs_length(resourcesReply))
        guard let outputs = xcb_randr_get_screen_resources_current_outputs(resourcesReply) else {
            throw LuminaError.monitorEnumerationFailed(reason: "XRandR returned no outputs")
        }

        var monitors: [Monitor] = []

        // Query each output
        for i in 0..<outputCount {
            let output = outputs[i]

            // Query output info
            let outputInfoCookie = xcb_randr_get_output_info(connection, output, UInt32(XCB_CURRENT_TIME))
            guard let outputInfoReply = xcb_randr_get_output_info_reply(connection, outputInfoCookie, nil) else {
                continue  // Skip outputs we can't query
            }
            defer { free(outputInfoReply) }

            // Only include connected outputs
            guard outputInfoReply.pointee.connection == UInt8(XCB_RANDR_CONNECTION_CONNECTED.rawValue) else {
                continue
            }

            // Only include outputs with active CRTC
            let crtc = outputInfoReply.pointee.crtc
            guard crtc != 0 else {
                continue  // Output is connected but not active (no CRTC assigned)
            }

            // Query CRTC info for position and current mode
            let crtcInfoCookie = xcb_randr_get_crtc_info(connection, crtc, UInt32(XCB_CURRENT_TIME))
            guard let crtcInfoReply = xcb_randr_get_crtc_info_reply(connection, crtcInfoCookie, nil) else {
                continue
            }
            defer { free(crtcInfoReply) }

            // Extract position and size
            let x = Int16(crtcInfoReply.pointee.x)
            let y = Int16(crtcInfoReply.pointee.y)
            let width = UInt16(crtcInfoReply.pointee.width)
            let height = UInt16(crtcInfoReply.pointee.height)

            // Extract output name
            let nameLength = Int(xcb_randr_get_output_info_name_length(outputInfoReply))
            let namePtr = xcb_randr_get_output_info_name(outputInfoReply)
            let name: String
            if let namePtr = namePtr, nameLength > 0 {
                let nameData = Data(bytes: namePtr, count: nameLength)
                name = String(data: nameData, encoding: .utf8) ?? "Unknown Monitor"
            } else {
                name = "Monitor \(i + 1)"
            }

            // Detect DPI and calculate scale factor
            let scaleFactor = detectScaleFactor(
                connection: connection,
                screen: screen,
                outputInfo: outputInfoReply,
                width: width,
                height: height
            )

            // Determine if this is the primary monitor
            // XRandR primary output detection
            let primaryCookie = xcb_randr_get_output_primary(connection, rootWindow)
            let primaryOutput: xcb_randr_output_t
            if let primaryReply = xcb_randr_get_output_primary_reply(connection, primaryCookie, nil) {
                primaryOutput = primaryReply.pointee.output
                free(primaryReply)
            } else {
                primaryOutput = 0
            }

            let isPrimary = (output == primaryOutput)

            // Build Monitor struct
            let monitor = Monitor(
                id: MonitorID(UInt64(output)),
                name: name,
                position: LogicalPosition(x: Float(x), y: Float(y)),
                size: LogicalSize(width: Float(width), height: Float(height)),
                workArea: LogicalRect(
                    origin: LogicalPosition(x: Float(x), y: Float(y)),
                    size: LogicalSize(width: Float(width), height: Float(height))
                ),  // Note: Work area calculation (excluding panels/docks) requires EWMH _NET_WORKAREA
                    // For now, work area = full size (simple implementation)
                scaleFactor: scaleFactor,
                isPrimary: isPrimary
            )

            monitors.append(monitor)
        }

        // Ensure at least one monitor
        guard !monitors.isEmpty else {
            throw LuminaError.monitorEnumerationFailed(reason: "No connected monitors found")
        }

        return monitors
    }

    /// Get the primary monitor using XRandR.
    ///
    /// The primary monitor is the one designated by the window manager or user
    /// as the main display. This is where new windows typically appear by default.
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - screen: Default screen
    /// - Returns: The primary monitor
    /// - Throws: LuminaError.monitorEnumerationFailed if no primary monitor found
    ///
    /// Example:
    /// ```swift
    /// let primary = try X11Monitor.primaryMonitor(connection: conn, screen: screen)
    /// print("Primary: \(primary.name) at \(primary.position)")
    /// ```
    public static func primaryMonitor(
        connection: OpaquePointer,
        screen: UnsafeMutablePointer<xcb_screen_t>
    ) throws -> Monitor {
        let monitors = try enumerateMonitors(connection: connection, screen: screen)

        // Find primary monitor
        if let primary = monitors.first(where: { $0.isPrimary }) {
            return primary
        }

        // Fallback: return first monitor if no primary marked
        if let first = monitors.first {
            return first
        }

        throw LuminaError.monitorEnumerationFailed(reason: "No primary monitor found")
    }

    // MARK: - DPI Detection

    /// Detect DPI scale factor for a monitor.
    ///
    /// DPI detection priority (highest to lowest):
    /// 1. XSETTINGS (Xft/Dpi property) - used by GNOME, KDE
    /// 2. Xft.dpi X resource - legacy fallback
    /// 3. Physical dimensions from EDID (mm_width/mm_height)
    /// 4. Default 96 DPI (1.0 scale factor)
    ///
    /// Scale factor calculation:
    /// - 96 DPI = 1.0x (standard)
    /// - 120 DPI = 1.25x
    /// - 144 DPI = 1.5x
    /// - 192 DPI = 2.0x (HiDPI)
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - screen: Default screen
    ///   - outputInfo: XRandR output info reply
    ///   - width: Current mode width in pixels
    ///   - height: Current mode height in pixels
    /// - Returns: Scale factor (typically 1.0, 1.25, 1.5, 2.0, etc.)
    private static func detectScaleFactor(
        connection: OpaquePointer,
        screen: UnsafeMutablePointer<xcb_screen_t>,
        outputInfo: UnsafeMutablePointer<xcb_randr_get_output_info_reply_t>,
        width: UInt16,
        height: UInt16
    ) -> Float {
        // Priority 1: Try XSETTINGS (not implemented in Milestone 1)
        // This requires parsing XSETTINGS_S0 window property, which is complex

        // Priority 2: Try Xft.dpi X resource (not implemented in Milestone 1)
        // This requires X resource database parsing via libX11

        // Priority 3: Calculate from physical dimensions
        let mmWidth = outputInfo.pointee.mm_width
        let mmHeight = outputInfo.pointee.mm_height

        if mmWidth > 0 && mmHeight > 0 {
            // Calculate DPI from physical dimensions
            // DPI = pixels / (mm / 25.4)
            let dpiX = Float(width) / (Float(mmWidth) / 25.4)
            let dpiY = Float(height) / (Float(mmHeight) / 25.4)
            let dpi = (dpiX + dpiY) / 2.0  // Average of X and Y DPI

            // Convert DPI to scale factor (96 DPI = 1.0x)
            let scaleFactor = dpi / 96.0

            // Clamp to reasonable range (0.5x to 4.0x)
            let clampedScale = max(0.5, min(4.0, scaleFactor))

            // Round to nearest 0.25 for common scale factors
            let roundedScale = round(clampedScale * 4.0) / 4.0

            return roundedScale
        }

        // Priority 4: Default to 96 DPI (1.0 scale factor)
        return 1.0
    }

    // MARK: - Monitor Change Notifications

    /// Subscribe to monitor configuration change events.
    ///
    /// This function enables XRandR notifications for screen configuration changes.
    /// When the monitor configuration changes (resolution, position, connection),
    /// the event loop will receive XCB_RANDR_SCREEN_CHANGE_NOTIFY events.
    ///
    /// Applications should call `enumerateMonitors()` again when receiving these
    /// events to update their internal monitor list.
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - screen: Default screen
    /// - Throws: LuminaError.x11ExtensionMissing if XRandR notification setup fails
    ///
    /// Example:
    /// ```swift
    /// try X11Monitor.subscribeToChanges(connection: conn, screen: screen)
    ///
    /// // In event loop:
    /// if responseType == XCB_RANDR_SCREEN_CHANGE_NOTIFY {
    ///     let monitors = try X11Monitor.enumerateMonitors(connection: conn, screen: screen)
    ///     print("Monitor configuration changed: \(monitors.count) monitor(s)")
    ///     eventQueue.append(.monitor(.configurationChanged))
    /// }
    /// ```
    public static func subscribeToChanges(
        connection: OpaquePointer,
        screen: UnsafeMutablePointer<xcb_screen_t>
    ) throws {
        let rootWindow = screen.pointee.root

        // Enable RandR screen change notifications
        let mask: UInt16 = UInt16(XCB_RANDR_NOTIFY_MASK_SCREEN_CHANGE.rawValue)
        let cookie = xcb_randr_select_input_checked(connection, rootWindow, mask)

        // Check for errors
        if let error = xcb_request_check(connection, cookie) {
            let errorCode = Int(error.pointee.error_code)
            free(error)
            throw LuminaError.x11ExtensionMissing(
                extension: "XRandR screen change notification (error code: \(errorCode))"
            )
        }
    }
}

// MARK: - Global Monitor Functions (Linux X11)

/// Internal namespace for Linux-specific clipboard implementations.
///
/// This struct is not meant to be instantiated directly. It provides
/// static methods that are called by the public Clipboard API when
/// running on Linux.
@MainActor
struct LinuxX11Monitor {
    private init() {}

    static func enumerateMonitors() throws -> [Monitor] {
        // This function should be called with application's XCB connection
        // For now, we'll throw an error indicating the app must be initialized
        throw LuminaError.invalidState(
            "Monitor enumeration requires initialized X11Application. Use Monitor.all() instead."
        )
    }

    static func primaryMonitor() throws -> Monitor {
        // This function should be called with application's XCB connection
        // For now, we'll throw an error indicating the app must be initialized
        throw LuminaError.invalidState(
            "Primary monitor detection requires initialized X11Application. Use Monitor.primary() instead."
        )
    }
}

#endif
