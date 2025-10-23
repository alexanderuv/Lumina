#if os(Linux)
import CXCBLinux
import Glibc

/// X11/XCB implementation of LuminaCursor using cursor font.
///
/// This implementation provides cursor appearance and visibility control on Linux X11
/// systems using XCB's cursor font facility. The cursor font is a standard X11 resource
/// that provides a set of predefined cursor shapes.
///
/// **Architecture:**
/// - Uses X11 cursor font (standard "cursor" font with predefined glyphs)
/// - Maps SystemCursor enum to cursor font glyph indices
/// - Creates cursors with `xcb_create_glyph_cursor()`
/// - Sets cursors on windows via `xcb_change_window_attributes()`
/// - Implements hide() using a 1x1 transparent pixmap
///
/// **Note:** Cursors are created on-demand and not cached. In a production implementation,
/// you may want to cache cursor objects to avoid repeated creation.
///
/// Example:
/// ```swift
/// let cursor = window.cursor()
/// cursor.set(.hand)  // Change to pointing hand
/// cursor.hide()      // Make cursor invisible
/// cursor.show()      // Restore cursor visibility
/// ```
@MainActor
struct X11Cursor: LuminaCursor {
    private let window: xcb_window_t
    private let connection: OpaquePointer

    // Cursor font glyphs (from X11 cursorfont.h)
    // The cursor font stores cursors as glyph pairs: (shape, mask)
    // Even numbers are shapes, odd numbers are their masks
    private enum CursorFont: UInt16 {
        case leftPtr = 68           // arrow
        case xterm = 152            // I-beam
        case crosshair = 34         // crosshair
        case hand2 = 60             // pointing hand
        case sbVDoubleArrow = 116   // vertical resize
        case sbHDoubleArrow = 108   // horizontal resize
        case bottomLeftCorner = 12  // NE-SW diagonal resize
        case bottomRightCorner = 14 // NW-SE diagonal resize
    }

    init(window: xcb_window_t, connection: OpaquePointer) {
        self.window = window
        self.connection = connection
    }

    func set(_ cursor: SystemCursor) {
        // Map SystemCursor to X11 cursor font glyph
        let glyph: CursorFont = switch cursor {
        case .arrow:
            .leftPtr
        case .ibeam:
            .xterm
        case .crosshair:
            .crosshair
        case .hand:
            .hand2
        case .resizeNS:
            .sbVDoubleArrow
        case .resizeEW:
            .sbHDoubleArrow
        case .resizeNESW:
            .bottomLeftCorner
        case .resizeNWSE:
            .bottomRightCorner
        }

        // Open cursor font
        let fontID = xcb_generate_id(connection)
        xcb_open_font(
            connection,
            fontID,
            6,  // Length of "cursor"
            "cursor"
        )

        // Create cursor from glyph
        let cursorID = xcb_generate_id(connection)
        xcb_create_glyph_cursor(
            connection,
            cursorID,
            fontID,
            fontID,
            glyph.rawValue,
            glyph.rawValue + 1,  // Cursor font has pairs (shape, mask)
            0, 0, 0,  // Foreground RGB (black)
            65535, 65535, 65535  // Background RGB (white)
        )

        // Set cursor on window
        let valueMask: UInt32 = XCB_CW_CURSOR.rawValue
        var valueList: [UInt32] = [cursorID]
        xcb_change_window_attributes(
            connection,
            window,
            valueMask,
            &valueList
        )

        // Close font (cursor persists)
        xcb_close_font(connection, fontID)

        // Flush to apply changes
        _ = xcb_flush_shim(connection)

        // Note: We don't free the cursor here as it's being used by the window.
        // The cursor will be automatically freed when the window is destroyed.
        // In a more sophisticated implementation, we would cache cursors.
    }

    func hide() {
        // Create an invisible cursor using a 1x1 transparent pixmap
        let pixmap = xcb_generate_id(connection)

        // Get root window to create pixmap
        let setup = xcb_get_setup_shim(connection)
        let screenIter = xcb_setup_roots_iterator_shim(setup)
        let screen = screenIter.data

        // Create 1x1 pixmap
        xcb_create_pixmap(
            connection,
            1,  // Depth
            pixmap,
            screen!.pointee.root,
            1, 1  // 1x1 size
        )

        // Create invisible cursor from pixmap
        let cursorID = xcb_generate_id(connection)
        xcb_create_cursor(
            connection,
            cursorID,
            pixmap,
            pixmap,
            0, 0, 0,  // Foreground (black)
            0, 0, 0,  // Background (black)
            0, 0      // Hotspot (0, 0)
        )

        // Set invisible cursor on window
        let valueMask: UInt32 = XCB_CW_CURSOR.rawValue
        var valueList: [UInt32] = [cursorID]
        xcb_change_window_attributes(
            connection,
            window,
            valueMask,
            &valueList
        )

        // Free pixmap (cursor persists)
        xcb_free_pixmap(connection, pixmap)

        // Flush to apply changes
        _ = xcb_flush_shim(connection)
    }

    func show() {
        // Restore default cursor (arrow)
        set(.arrow)
    }
}

extension X11Cursor: @unchecked Sendable {}

#endif
