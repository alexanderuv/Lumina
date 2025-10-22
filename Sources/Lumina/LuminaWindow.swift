/// Internal protocol for platform-specific window implementations.
///
/// This protocol is NOT part of the public API. It defines the contract
/// that platform backends (macOS, Windows) must implement to provide
/// window functionality.
///
/// Thread Safety: All methods must be called from the main thread (@MainActor).
///
/// Platform Implementations:
/// - macOS: Wraps NSWindow with coordinate conversion (AppKit origin is bottom-left)
/// - Windows: Wraps HWND with Win32 API calls (origin is top-left)
@MainActor
public protocol LuminaWindow: Sendable, ~Copyable {
    /// Unique identifier for this window.
    ///
    /// The ID must remain stable for the lifetime of the window and should
    /// be used to associate events with this window instance.
    var id: WindowID { get }

    /// Show the window (make it visible).
    ///
    /// Implementation notes:
    /// - macOS: Use makeKeyAndOrderFront or orderFront
    /// - Windows: Use ShowWindow(SW_SHOW)
    /// - Should generate a window visibility event if appropriate
    func show()

    /// Hide the window (make it invisible).
    ///
    /// Implementation notes:
    /// - macOS: Use orderOut
    /// - Windows: Use ShowWindow(SW_HIDE)
    /// - Window state is preserved, can be shown again later
    func hide()

    /// Close the window and release resources (consumes self).
    ///
    /// After calling this method, the window is no longer valid and should
    /// not be used. This method consumes ownership of the window.
    ///
    /// Implementation notes:
    /// - macOS: Call close() on NSWindow, release window delegate
    /// - Windows: Call DestroyWindow(hwnd)
    /// - Should generate a window closed event
    consuming func close()

    /// Set the window title.
    ///
    /// Implementation notes:
    /// - macOS: Set NSWindow.title
    /// - Windows: Use SetWindowText
    /// - Uses borrowing parameter to avoid unnecessary string copies
    ///
    /// - Parameter title: The new window title
    func setTitle(_ title: String)

    /// Get the current window size (logical coordinates).
    ///
    /// Returns the size of the window's content area in logical points,
    /// excluding title bar and borders.
    ///
    /// Implementation notes:
    /// - macOS: Use contentRect.size, already in logical points
    /// - Windows: Use GetClientRect, convert to logical using DPI
    ///
    /// - Returns: Current logical size of the window content area
    func size() -> LogicalSize

    /// Resize the window programmatically.
    ///
    /// Implementation notes:
    /// - macOS: Use setFrame with contentRect
    /// - Windows: Use SetWindowPos, convert logical to physical pixels
    /// - Should respect min/max size constraints
    /// - Should generate a window resized event
    ///
    /// - Parameter size: The new logical size for the window
    func resize(_ size: LogicalSize)

    /// Get the current window position (screen coordinates).
    ///
    /// Returns the position of the window's top-left corner in screen
    /// coordinates (logical points).
    ///
    /// Implementation notes:
    /// - macOS: Convert from bottom-left origin to top-left
    /// - Windows: Use GetWindowRect, already top-left origin
    ///
    /// - Returns: Current logical position of the window
    func position() -> LogicalPosition

    /// Move the window to a new position.
    ///
    /// Implementation notes:
    /// - macOS: Use setFrameTopLeftPoint, convert coordinate systems
    /// - Windows: Use SetWindowPos
    /// - Should generate a window moved event
    ///
    /// - Parameter position: The new logical position for the window's top-left corner
    func moveTo(_ position: LogicalPosition)

    /// Set minimum window size constraint.
    ///
    /// Prevents the window from being resized smaller than the specified size.
    /// Pass nil to remove the constraint.
    ///
    /// Implementation notes:
    /// - macOS: Use setContentMinSize
    /// - Windows: Handle in WM_GETMINMAXINFO message
    ///
    /// - Parameter size: Minimum logical size, or nil to remove constraint
    func setMinSize(_ size: LogicalSize?)

    /// Set maximum window size constraint.
    ///
    /// Prevents the window from being resized larger than the specified size.
    /// Pass nil to remove the constraint.
    ///
    /// Implementation notes:
    /// - macOS: Use setContentMaxSize
    /// - Windows: Handle in WM_GETMINMAXINFO message
    ///
    /// - Parameter size: Maximum logical size, or nil to remove constraint
    func setMaxSize(_ size: LogicalSize?)

    /// Request keyboard focus for this window.
    ///
    /// Makes this window the active window that receives keyboard input.
    ///
    /// Implementation notes:
    /// - macOS: Use makeKeyAndOrderFront
    /// - Windows: Use SetForegroundWindow
    /// - Should generate focused/unfocused events
    func requestFocus()

    /// Get the current scale factor (DPI) for this window.
    ///
    /// Returns the ratio of physical pixels to logical points. Common values:
    /// - 1.0: Standard DPI (96 DPI on Windows, 72 DPI on macOS)
    /// - 2.0: Retina/HiDPI (192 DPI on Windows, 144 DPI on macOS)
    ///
    /// Implementation notes:
    /// - macOS: Use backingScaleFactor
    /// - Windows: GetDpiForWindow / 96.0
    /// - May change when window moves between monitors
    ///
    /// - Returns: Current scale factor for this window
    func scaleFactor() -> Float

    /// Request that the window be redrawn.
    ///
    /// Triggers a redraw event that will be delivered to the application's event loop.
    /// The application should respond by rendering the window content.
    ///
    /// This method is used for:
    /// - Application-driven rendering (animations, updates)
    /// - Frame-paced rendering loops
    /// - Responding to data changes that require visual updates
    ///
    /// Implementation notes:
    /// - macOS: Use setNeedsDisplay() and mark for CADisplayLink delivery
    /// - Windows: Use InvalidateRect()
    /// - Linux X11: Use xcb_clear_area() to force expose event
    /// - Linux Wayland: Use wl_surface_damage() and wl_surface_commit()
    ///
    /// Example:
    /// ```swift
    /// // Request redraw after data changes
    /// model.updateData()
    /// window.requestRedraw()
    ///
    /// // In event loop:
    /// if case .redraw(.requested(let windowID, _)) = event {
    ///     render(windowID)
    /// }
    /// ```
    func requestRedraw()

    /// Toggle window decorations (title bar, borders, close button).
    ///
    /// When decorations are disabled, the window becomes borderless, with no
    /// title bar or system controls. This is useful for custom window chrome,
    /// splash screens, or fullscreen-like experiences.
    ///
    /// Platform support varies - use `capabilities().supportsDecorationToggle`
    /// to check before calling.
    ///
    /// Implementation notes:
    /// - macOS: Toggle styleMask between .titled and .borderless
    /// - Windows: Toggle WS_OVERLAPPEDWINDOW vs WS_POPUP style
    /// - Linux X11: Use _MOTIF_WM_HINTS property
    /// - Linux Wayland: Use xdg-decoration protocol if available
    ///
    /// - Parameter decorated: true to show decorations, false to hide
    /// - Throws: `LuminaError.unsupportedPlatformFeature` if not supported
    ///
    /// Example:
    /// ```swift
    /// let caps = window.capabilities()
    /// if caps.supportsDecorationToggle {
    ///     try window.setDecorated(false)  // Borderless window
    /// }
    /// ```
    func setDecorated(_ decorated: Bool) throws

    /// Set window always-on-top behavior.
    ///
    /// When enabled, the window stays above other windows even when not focused.
    /// This is useful for tool palettes, floating toolbars, or notifications.
    ///
    /// Platform support varies - use `capabilities().supportsAlwaysOnTop`
    /// to check before calling.
    ///
    /// Implementation notes:
    /// - macOS: Set window.level to .floating or .normal
    /// - Windows: Use SetWindowPos with HWND_TOPMOST or HWND_NOTOPMOST
    /// - Linux X11: Use _NET_WM_STATE_ABOVE property
    /// - Linux Wayland: No standard protocol (compositor-dependent)
    ///
    /// - Parameter alwaysOnTop: true to keep window on top, false for normal behavior
    /// - Throws: `LuminaError.unsupportedPlatformFeature` if not supported
    ///
    /// Example:
    /// ```swift
    /// let caps = window.capabilities()
    /// if caps.supportsAlwaysOnTop {
    ///     try window.setAlwaysOnTop(true)  // Floating window
    /// }
    /// ```
    func setAlwaysOnTop(_ alwaysOnTop: Bool) throws

    /// Set window transparency (alpha channel support).
    ///
    /// When enabled, the window can use per-pixel alpha blending for effects
    /// like rounded corners, drop shadows, or custom window shapes.
    ///
    /// Platform support varies - use `capabilities().supportsTransparency`
    /// to check before calling.
    ///
    /// Implementation notes:
    /// - macOS: Set isOpaque to false, backgroundColor to clear
    /// - Windows: Enable WS_EX_LAYERED extended style
    /// - Linux X11: Requires ARGB visual (rarely supported)
    /// - Linux Wayland: Native ARGB8888 surface support
    ///
    /// - Parameter transparent: true to enable transparency, false for opaque
    /// - Throws: `LuminaError.unsupportedPlatformFeature` if not supported
    ///
    /// Example:
    /// ```swift
    /// let caps = window.capabilities()
    /// if caps.supportsTransparency {
    ///     try window.setTransparent(true)
    ///     // Now render with alpha channel
    /// }
    /// ```
    func setTransparent(_ transparent: Bool) throws

    /// Query window capabilities for this platform.
    ///
    /// Returns information about which window features are supported on this
    /// platform. Use this to determine whether to enable UI for optional features.
    ///
    /// Example:
    /// ```swift
    /// let caps = window.capabilities()
    /// if caps.supportsTransparency {
    ///     // Show "Enable transparency" checkbox
    /// }
    /// if caps.supportsAlwaysOnTop {
    ///     // Show "Always on top" checkbox
    /// }
    /// ```
    ///
    /// - Returns: WindowCapabilities struct describing platform support
    func capabilities() -> WindowCapabilities

    /// Get the monitor that this window is currently on.
    ///
    /// Returns the monitor containing the majority of the window's area.
    /// If the window spans multiple monitors, the "primary" monitor is
    /// typically the one containing the title bar or center of the window.
    ///
    /// Implementation notes:
    /// - macOS: Use window.screen and convert to Monitor
    /// - Windows: Use MonitorFromWindow(MONITOR_DEFAULTTONEAREST)
    /// - Linux: Query window position and intersect with monitor list
    ///
    /// - Returns: The monitor this window is on
    /// - Throws: `LuminaError.monitorEnumerationFailed` if query fails
    ///
    /// Example:
    /// ```swift
    /// let monitor = try window.currentMonitor()
    /// print("Window is on monitor: \(monitor.name)")
    /// print("Monitor scale factor: \(monitor.scaleFactor)x")
    /// ```
    func currentMonitor() throws -> Monitor

    /// Get a cursor controller for this window.
    ///
    /// Returns a cursor instance that can be used to change the cursor
    /// appearance and visibility. This replaces the previous static Cursor API
    /// with a protocol-based design.
    ///
    /// Implementation notes:
    /// - macOS: Returns MacCursor wrapping NSCursor calls
    /// - Windows: Returns WinCursor wrapping Win32 cursor APIs
    /// - Linux X11: Returns X11Cursor wrapping Xcursor library
    /// - Linux Wayland: Returns WaylandCursor using cursor-shape-v1
    ///
    /// - Returns: A cursor controller for this window
    ///
    /// Example:
    /// ```swift
    /// let cursor = window.cursor()
    /// cursor.set(.hand)  // Change to hand cursor
    /// cursor.hide()      // Hide cursor
    /// cursor.show()      // Show cursor
    /// ```
    func cursor() -> any LuminaCursor
}
