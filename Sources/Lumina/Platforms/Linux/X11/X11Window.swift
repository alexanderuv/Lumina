#if os(Linux)
import CXCBLinux
import Glibc

/// X11/XCB implementation of LuminaWindow.
///
/// This implementation provides window management on Linux X11 systems using XCB.
/// It handles window creation, event routing, size/position management, and
/// EWMH window manager interactions.
///
/// **Do not instantiate this type directly.** Windows are created through
/// `LuminaApp.createWindow()`.
///
/// Example:
/// ```swift
/// var app = try createLuminaApp()
/// var window = try app.createWindow(
///     title: "X11 Window",
///     size: LogicalSize(width: 800, height: 600),
///     resizable: true,
///     monitor: nil
/// ).get()
/// window.show()
/// ```
@MainActor
public struct X11Window: LuminaWindow {
    /// Unique Lumina window ID
    public let id: WindowID

    /// XCB window handle
    internal let xcbWindow: xcb_window_t

    /// XCB connection (borrowed from application)
    private let connection: OpaquePointer

    /// Cached atoms (borrowed from application)
    private let atoms: X11Atoms

    /// Minimum size constraint
    private var minSize: LogicalSize?

    /// Maximum size constraint
    private var maxSize: LogicalSize?

    /// Create a new X11 window.
    ///
    /// This is an internal method called by X11Application.createWindow().
    ///
    /// - Parameters:
    ///   - connection: XCB connection
    ///   - screen: Target screen
    ///   - atoms: Cached atom IDs
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether window can be resized
    /// - Returns: Newly created window
    /// - Throws: `LuminaError.windowCreationFailed` if creation fails
    static func create(
        connection: OpaquePointer,
        screen: UnsafeMutablePointer<xcb_screen_t>,
        atoms: X11Atoms,
        title: String,
        size: LogicalSize,
        resizable: Bool
    ) throws -> X11Window {
        // Generate unique window ID
        let windowID = xcb_generate_id(connection)

        // Event mask: what events we want to receive
        let valueMask: UInt32 = XCB_CW_BACK_PIXEL.rawValue | XCB_CW_EVENT_MASK.rawValue
        var valueList: [UInt32] = [
            screen.pointee.white_pixel,  // Background color
            XCB_EVENT_MASK_EXPOSURE.rawValue |
            XCB_EVENT_MASK_STRUCTURE_NOTIFY.rawValue |
            XCB_EVENT_MASK_BUTTON_PRESS.rawValue |
            XCB_EVENT_MASK_BUTTON_RELEASE.rawValue |
            XCB_EVENT_MASK_POINTER_MOTION.rawValue |
            XCB_EVENT_MASK_ENTER_WINDOW.rawValue |
            XCB_EVENT_MASK_LEAVE_WINDOW.rawValue |
            XCB_EVENT_MASK_KEY_PRESS.rawValue |
            XCB_EVENT_MASK_KEY_RELEASE.rawValue |
            XCB_EVENT_MASK_FOCUS_CHANGE.rawValue
        ]

        // Create window
        let cookie = xcb_create_window(
            connection,
            UInt8(XCB_COPY_FROM_PARENT),  // Depth (inherit from parent)
            windowID,
            screen.pointee.root,   // Parent window (root)
            0, 0,                  // Position (will be set by WM)
            UInt16(size.width),
            UInt16(size.height),
            0,                     // Border width
            UInt16(XCB_WINDOW_CLASS_INPUT_OUTPUT.rawValue),
            screen.pointee.root_visual,
            valueMask,
            &valueList
        )

        // Check for errors
        let error = xcb_request_check(connection, cookie)
        if let error = error {
            let errorCode = Int(error.pointee.error_code)
            free(error)
            throw LuminaError.windowCreationFailed(reason: "XCB create_window failed with error code \(errorCode)")
        }

        // Set window title using UTF8_STRING
        title.withCString { cString in
            let length = UInt32(strlen(cString))
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                windowID,
                atoms.NET_WM_NAME,
                atoms.UTF8_STRING,
                8,  // Format: 8-bit data
                length,
                cString
            )
        }

        // Set WM_PROTOCOLS to handle close button
        var protocols = [atoms.WM_DELETE_WINDOW]
        xcb_change_property(
            connection,
            UInt8(XCB_PROP_MODE_REPLACE.rawValue),
            windowID,
            atoms.WM_PROTOCOLS,
            XCB_ATOM_ATOM.rawValue,
            32,  // Format: 32-bit atoms
            1,   // Number of atoms
            &protocols
        )

        // Flush to ensure window is created
        _ = xcb_flush_shim(connection)

        // Create Lumina window struct
        return X11Window(
            id: WindowID(),
            xcbWindow: windowID,
            connection: connection,
            atoms: atoms,
            minSize: nil,
            maxSize: nil
        )
    }

    public mutating func show() {
        xcb_map_window(connection, xcbWindow)
        _ = xcb_flush_shim(connection)
    }

    public mutating func hide() {
        xcb_unmap_window(connection, xcbWindow)
        _ = xcb_flush_shim(connection)
    }

    public consuming func close() {
        xcb_destroy_window(connection, xcbWindow)
        _ = xcb_flush_shim(connection)
    }

    public mutating func setTitle(_ title: String) {
        title.withCString { cString in
            let length = UInt32(strlen(cString))
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                xcbWindow,
                atoms.NET_WM_NAME,
                atoms.UTF8_STRING,
                8,
                length,
                cString
            )
        }
        _ = xcb_flush_shim(connection)
    }

    public func size() -> LogicalSize {
        // Query geometry from X11 server (like Windows' GetClientRect)
        let cookie = xcb_get_geometry(connection, xcbWindow)
        guard let reply = xcb_get_geometry_reply(connection, cookie, nil) else {
            // If query fails, return zero size
            return LogicalSize(width: 0, height: 0)
        }
        defer { free(reply) }

        return LogicalSize(
            width: Float(reply.pointee.width),
            height: Float(reply.pointee.height)
        )
    }

    public mutating func resize(_ size: LogicalSize) {
        // Configure window with new size
        var values: [UInt32] = [UInt32(size.width), UInt32(size.height)]
        xcb_configure_window(
            connection,
            xcbWindow,
            UInt16(XCB_CONFIG_WINDOW_WIDTH.rawValue | XCB_CONFIG_WINDOW_HEIGHT.rawValue),
            &values
        )
        _ = xcb_flush_shim(connection)
    }

    public func position() -> LogicalPosition {
        // Query geometry from X11 server (like Windows' GetWindowRect)
        let cookie = xcb_get_geometry(connection, xcbWindow)
        guard let reply = xcb_get_geometry_reply(connection, cookie, nil) else {
            // If query fails, return zero position
            return LogicalPosition(x: 0, y: 0)
        }
        defer { free(reply) }

        return LogicalPosition(
            x: Float(reply.pointee.x),
            y: Float(reply.pointee.y)
        )
    }

    public mutating func moveTo(_ position: LogicalPosition) {
        var values: [UInt32] = [UInt32(position.x), UInt32(position.y)]
        xcb_configure_window(
            connection,
            xcbWindow,
            UInt16(XCB_CONFIG_WINDOW_X.rawValue | XCB_CONFIG_WINDOW_Y.rawValue),
            &values
        )
        _ = xcb_flush_shim(connection)
    }

    public mutating func setMinSize(_ size: LogicalSize?) {
        minSize = size
        updateSizeHints()
    }

    public mutating func setMaxSize(_ size: LogicalSize?) {
        maxSize = size
        updateSizeHints()
    }

    private func updateSizeHints() {
        // WM_NORMAL_HINTS using ICCCM size hints structure
        // This is simplified - a full implementation would use xcb_icccm library
        // For now, we'll skip this as it requires more complex structure setup
        // TODO: Implement proper ICCCM size hints
    }

    public mutating func requestFocus() {
        // Request input focus
        xcb_set_input_focus(
            connection,
            UInt8(XCB_INPUT_FOCUS_POINTER_ROOT.rawValue),
            xcbWindow,
            UInt32(XCB_CURRENT_TIME)
        )
        _ = xcb_flush_shim(connection)
    }

    public func scaleFactor() -> Float {
        // X11 DPI scaling
        // TODO: Implement proper DPI detection via Xft.dpi or XSETTINGS
        // For now, return 1.0 (will be implemented in X11Monitor)
        return 1.0
    }

    public mutating func requestRedraw() {
        // Force an expose event by clearing a 1x1 area
        xcb_clear_area(
            connection,
            1,  // exposures = true (generate expose event)
            xcbWindow,
            0, 0,  // x, y
            1, 1   // width, height
        )
        _ = xcb_flush_shim(connection)
    }

    public mutating func setDecorated(_ decorated: Bool) throws {
        // Use Motif WM hints to control decorations
        struct MotifWMHints {
            var flags: UInt32 = 2  // MWM_HINTS_DECORATIONS
            var functions: UInt32 = 0
            var decorations: UInt32
            var inputMode: Int32 = 0
            var status: UInt32 = 0
        }

        var hints = MotifWMHints(decorations: decorated ? 1 : 0)
        _ = withUnsafeBytes(of: &hints) { bytes in
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                xcbWindow,
                atoms.MOTIF_WM_HINTS,
                atoms.MOTIF_WM_HINTS,
                32,  // Format: 32-bit data
                5,   // 5 fields in the structure
                bytes.baseAddress
            )
        }
        _ = xcb_flush_shim(connection)
    }

    public mutating func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        // Use _NET_WM_STATE_ABOVE to set always-on-top
        if alwaysOnTop {
            var state = atoms.NET_WM_STATE_ABOVE
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_APPEND.rawValue),
                xcbWindow,
                atoms.NET_WM_STATE,
                XCB_ATOM_ATOM.rawValue,
                32,
                1,
                &state
            )
        } else {
            // Remove _NET_WM_STATE_ABOVE by replacing with empty property
            xcb_change_property(
                connection,
                UInt8(XCB_PROP_MODE_REPLACE.rawValue),
                xcbWindow,
                atoms.NET_WM_STATE,
                XCB_ATOM_ATOM.rawValue,
                32,
                0,
                nil
            )
        }
        _ = xcb_flush_shim(connection)
    }

    public mutating func setTransparent(_ transparent: Bool) throws {
        // X11 transparency requires ARGB visual which must be set at window creation
        // Cannot be changed after creation
        throw LuminaError.unsupportedPlatformFeature(
            feature: "transparency (requires ARGB visual at window creation)"
        )
    }

    public func capabilities() -> WindowCapabilities {
        return WindowCapabilities(
            supportsTransparency: false,  // Requires ARGB visual at creation
            supportsAlwaysOnTop: true,    // Via _NET_WM_STATE_ABOVE
            supportsDecorationToggle: true,  // Via _MOTIF_WM_HINTS
            supportsClientSideDecorations: false  // X11 uses server-side decorations
        )
    }

    public func currentMonitor() throws -> Monitor {
        // Monitor detection will be implemented in X11Monitor
        // For now, return a placeholder
        throw LuminaError.monitorEnumerationFailed(reason: "X11Monitor not yet implemented")
    }

    public func cursor() -> any LuminaCursor {
        // Cursor implementation will come later
        // For now, return a placeholder that conforms to the protocol
        return X11Cursor()
    }
}

/// Placeholder cursor implementation for X11
@MainActor
private struct X11Cursor: LuminaCursor {
    func set(_ cursor: SystemCursor) {
        // TODO: Implement X11 cursor support
    }

    func hide() {
        // TODO: Implement cursor hide
    }

    func show() {
        // TODO: Implement cursor show
    }
}

#endif
