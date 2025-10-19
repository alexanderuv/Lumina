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
internal protocol PlatformWindow: Sendable {
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
    mutating func show()

    /// Hide the window (make it invisible).
    ///
    /// Implementation notes:
    /// - macOS: Use orderOut
    /// - Windows: Use ShowWindow(SW_HIDE)
    /// - Window state is preserved, can be shown again later
    mutating func hide()

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
    mutating func setTitle(_ title: String)

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
    mutating func resize(_ size: LogicalSize)

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
    mutating func moveTo(_ position: LogicalPosition)

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
    mutating func setMinSize(_ size: LogicalSize?)

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
    mutating func setMaxSize(_ size: LogicalSize?)

    /// Request keyboard focus for this window.
    ///
    /// Makes this window the active window that receives keyboard input.
    ///
    /// Implementation notes:
    /// - macOS: Use makeKeyAndOrderFront
    /// - Windows: Use SetForegroundWindow
    /// - Should generate focused/unfocused events
    mutating func requestFocus()

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
}
