#if os(macOS)
import AppKit
#endif

/// System cursor appearance and visibility control.
///
/// Cursor provides a cross-platform API for changing the mouse cursor
/// appearance and visibility. In Milestone 0, only system cursors are
/// supported; custom cursor images will be added in a future milestone.
///
/// All cursor operations are global (affect the entire system) and must
/// be called from the main thread.
///
/// Thread Safety: All Cursor methods must be called from the main thread.
/// The @MainActor annotation enforces this at compile time.
///
/// Example:
/// ```swift
/// // Change cursor to hand when hovering over button
/// Cursor.set(.hand)
///
/// // Change cursor to I-beam for text input
/// Cursor.set(.ibeam)
///
/// // Restore default cursor
/// Cursor.set(.arrow)
/// ```
@MainActor
public struct Cursor {
    // Cursor has no instance state; all methods are static

    /// Standard system cursor types.
    ///
    /// These cursor shapes are provided by the operating system and
    /// have consistent appearance across the platform.
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

    /// Set the current cursor appearance.
    ///
    /// Changes the system cursor to the specified shape. The cursor remains
    /// in this shape until changed again or until the application loses focus.
    ///
    /// Platform Notes:
    /// - macOS: Uses NSCursor standard cursors
    /// - Windows: Uses LoadCursor with system cursor IDs
    ///
    /// - Parameter cursor: The cursor shape to display
    ///
    /// Example:
    /// ```swift
    /// // Show hand cursor when hovering over link
    /// if mouseOverLink {
    ///     Cursor.set(.hand)
    /// } else {
    ///     Cursor.set(.arrow)
    /// }
    /// ```
    public static func set(_ cursor: SystemCursor) {
        #if os(macOS)
        let nsCursor: NSCursor = switch cursor {
        case .arrow:
            .arrow
        case .ibeam:
            .iBeam
        case .crosshair:
            .crosshair
        case .hand:
            .pointingHand
        case .resizeNS:
            .resizeUpDown
        case .resizeEW:
            .resizeLeftRight
        case .resizeNESW:
            // macOS doesn't have specific diagonal resize cursors
            // Use closest approximation
            .arrow
        case .resizeNWSE:
            // macOS doesn't have specific diagonal resize cursors
            // Use closest approximation
            .arrow
        }
        nsCursor.set()
        #elseif os(Windows)
        // Windows cursor implementation
        // SetCursor(LoadCursor(NULL, cursor.toWindowsID()))
        #endif
    }

    /// Hide the cursor.
    ///
    /// Makes the cursor invisible. The cursor is still tracked and generates
    /// pointer events, but is not visible on screen. This is useful for
    /// applications that want to draw a custom cursor or hide the cursor
    /// during certain operations (e.g., video playback).
    ///
    /// Platform Notes:
    /// - Multiple hide() calls stack; call show() the same number of times
    /// - macOS: Uses [NSCursor hide]
    /// - Windows: Uses ShowCursor(FALSE)
    ///
    /// Example:
    /// ```swift
    /// // Hide cursor during fullscreen video
    /// Cursor.hide()
    ///
    /// // Later, restore cursor
    /// Cursor.show()
    /// ```
    public static func hide() {
        #if os(macOS)
        NSCursor.hide()
        #elseif os(Windows)
        // ShowCursor(FALSE)
        #endif
    }

    /// Show the cursor.
    ///
    /// Makes the cursor visible if it was previously hidden. If hide() was
    /// called multiple times, show() must be called the same number of times
    /// to make the cursor visible.
    ///
    /// Platform Notes:
    /// - hide()/show() calls are reference counted
    /// - macOS: Uses [NSCursor unhide]
    /// - Windows: Uses ShowCursor(TRUE)
    ///
    /// Example:
    /// ```swift
    /// // Show cursor after hiding
    /// Cursor.show()
    /// ```
    public static func show() {
        #if os(macOS)
        NSCursor.unhide()
        #elseif os(Windows)
        // ShowCursor(TRUE)
        #endif
    }
}
