/// Protocol for cursor appearance and visibility control.
///
/// LuminaCursor provides a unified interface for changing the mouse cursor
/// appearance and visibility. Get a cursor instance from a window via
/// `window.cursor()`.
///
/// This replaces the previous static Cursor API with a protocol-based design
/// that aligns with Lumina's architectural patterns.
///
/// Thread Safety: All cursor methods must be called from the main thread.
/// The @MainActor annotation enforces this at compile time.
///
/// Usage:
/// ```swift
/// let cursor = window.cursor()
/// cursor.set(.hand)
/// cursor.hide()
/// cursor.show()
/// ```
///
/// Example:
/// ```swift
/// let cursor = window.cursor()
///
/// // Change cursor to hand when hovering over button
/// cursor.set(.hand)
///
/// // Change cursor to I-beam for text input
/// cursor.set(.ibeam)
///
/// // Hide cursor during fullscreen video
/// cursor.hide()
///
/// // Restore cursor visibility
/// cursor.show()
/// ```
@MainActor
public protocol LuminaCursor: Sendable {
    /// Set the current cursor appearance.
    ///
    /// Changes the system cursor to the specified shape. The cursor remains
    /// in this shape until changed again or until the application loses focus.
    ///
    /// Platform Notes:
    /// - macOS: Uses NSCursor standard cursors
    /// - Windows: Uses LoadCursor with system cursor IDs
    /// - Linux X11: Uses system cursor resources
    /// - Linux Wayland: Uses cursor-shape-v1 protocol
    ///
    /// - Parameter cursor: The cursor shape to display
    ///
    /// Example:
    /// ```swift
    /// let cursor = window.cursor()
    /// // Show hand cursor when hovering over link
    /// if mouseOverLink {
    ///     cursor.set(.hand)
    /// } else {
    ///     cursor.set(.arrow)
    /// }
    /// ```
    func set(_ cursor: SystemCursor)

    /// Hide the cursor.
    ///
    /// Makes the cursor invisible. The cursor is still tracked and generates
    /// pointer events, but is not visible on screen. This is useful for
    /// applications that want to draw a custom cursor or hide the cursor
    /// during certain operations (e.g., video playback).
    ///
    /// Platform Notes:
    /// - Multiple hide() calls may stack; call show() the same number of times
    /// - macOS: Uses [NSCursor hide]
    /// - Windows: Uses ShowCursor(FALSE)
    /// - Linux: Platform-specific cursor visibility control
    ///
    /// Example:
    /// ```swift
    /// let cursor = window.cursor()
    /// // Hide cursor during fullscreen video
    /// cursor.hide()
    ///
    /// // Later, restore cursor
    /// cursor.show()
    /// ```
    func hide()

    /// Show the cursor.
    ///
    /// Makes the cursor visible if it was previously hidden. If hide() was
    /// called multiple times, show() may need to be called the same number
    /// of times to make the cursor visible (platform-dependent).
    ///
    /// Platform Notes:
    /// - hide()/show() calls may be reference counted on some platforms
    /// - macOS: Uses [NSCursor unhide]
    /// - Windows: Uses ShowCursor(TRUE)
    /// - Linux: Platform-specific cursor visibility control
    ///
    /// Example:
    /// ```swift
    /// let cursor = window.cursor()
    /// // Show cursor after hiding
    /// cursor.show()
    /// ```
    func show()
}

/// Standard system cursor types.
///
/// These cursor shapes are provided by the operating system and
/// have consistent appearance across the platform. Currently,
/// only system cursors are supported; custom cursor images will be
/// added in the future.
public enum SystemCursor: Sendable {
    /// Default arrow pointer
    case arrow

    /// I-beam for text selection
    case ibeam

    /// Crosshair for precision selection
    case crosshair

    /// Pointing hand for clickable items
    case hand

    /// Vertical resize cursor (north-south)
    case resizeNS

    /// Horizontal resize cursor (east-west)
    case resizeEW

    /// Diagonal resize cursor (northeast-southwest)
    case resizeNESW

    /// Diagonal resize cursor (northwest-southeast)
    case resizeNWSE
}
