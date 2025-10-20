#if os(Linux)
import CXCBLinux
import Glibc  // For free()

/// Cached X11 atom identifiers for common window manager protocols.
///
/// X11 atoms are integer identifiers for string names used in window manager
/// communication (ICCCM and EWMH protocols). Caching these atoms at startup
/// avoids repeated round-trips to the X server during runtime.
///
/// This struct is initialized once per connection and provides fast access
/// to frequently used atom IDs.
///
/// Example usage:
/// ```swift
/// let atoms = try X11Atoms.cache(connection: connection)
///
/// // Set window title using cached UTF8_STRING atom
/// xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window,
///                     atoms.NET_WM_NAME, atoms.UTF8_STRING, 8,
///                     UInt32(title.utf8.count), title)
/// ```
@MainActor
public struct X11Atoms: Sendable {
    // ICCCM (Inter-Client Communication Conventions Manual)
    public let WM_PROTOCOLS: xcb_atom_t
    public let WM_DELETE_WINDOW: xcb_atom_t

    // EWMH (Extended Window Manager Hints)
    public let NET_WM_NAME: xcb_atom_t
    public let NET_WM_STATE: xcb_atom_t
    public let NET_WM_STATE_ABOVE: xcb_atom_t
    public let NET_WM_STATE_FULLSCREEN: xcb_atom_t

    // Motif Window Manager Hints (for decoration control)
    public let MOTIF_WM_HINTS: xcb_atom_t

    // Clipboard
    public let CLIPBOARD: xcb_atom_t

    // String encoding
    public let UTF8_STRING: xcb_atom_t

    /// Creates and caches all required atoms for the given connection.
    ///
    /// This method sends intern_atom requests for all required atoms and waits
    /// for replies. It should be called once during application initialization.
    ///
    /// - Parameter connection: Active XCB connection to the X server
    /// - Returns: Cached atom identifiers
    /// - Throws: `LuminaError.x11ExtensionMissing` if any required atom cannot be interned
    ///
    /// Example:
    /// ```swift
    /// let connection = xcb_connect(nil, nil)
    /// defer { xcb_disconnect(connection) }
    ///
    /// do {
    ///     let atoms = try X11Atoms.cache(connection: connection)
    ///     // Use atoms for window management
    /// } catch {
    ///     print("Failed to cache atoms: \(error)")
    /// }
    /// ```
    public static func cache(connection: OpaquePointer) throws -> X11Atoms {
        // Intern all required atoms
        let cookies: [(name: String, cookie: xcb_intern_atom_cookie_t)] = [
            // ICCCM
            ("WM_PROTOCOLS", xcb_intern_atom(connection, 0, 12, "WM_PROTOCOLS")),
            ("WM_DELETE_WINDOW", xcb_intern_atom(connection, 0, 16, "WM_DELETE_WINDOW")),

            // EWMH
            ("_NET_WM_NAME", xcb_intern_atom(connection, 0, 12, "_NET_WM_NAME")),
            ("_NET_WM_STATE", xcb_intern_atom(connection, 0, 13, "_NET_WM_STATE")),
            ("_NET_WM_STATE_ABOVE", xcb_intern_atom(connection, 0, 19, "_NET_WM_STATE_ABOVE")),
            ("_NET_WM_STATE_FULLSCREEN", xcb_intern_atom(connection, 0, 24, "_NET_WM_STATE_FULLSCREEN")),

            // Motif WM Hints
            ("_MOTIF_WM_HINTS", xcb_intern_atom(connection, 0, 15, "_MOTIF_WM_HINTS")),

            // Clipboard
            ("CLIPBOARD", xcb_intern_atom(connection, 0, 9, "CLIPBOARD")),

            // String encoding
            ("UTF8_STRING", xcb_intern_atom(connection, 0, 11, "UTF8_STRING"))
        ]

        // Retrieve replies
        var atoms: [xcb_atom_t] = []
        for (name, cookie) in cookies {
            var error: UnsafeMutablePointer<xcb_generic_error_t>?
            guard let reply = xcb_intern_atom_reply(connection, cookie, &error) else {
                if let error = error {
                    let errorCode = Int(error.pointee.error_code)
                    free(error)
                    throw LuminaError.x11ExtensionMissing(extension: "Atom '\(name)' (error code: \(errorCode))")
                } else {
                    throw LuminaError.x11ExtensionMissing(extension: "Atom '\(name)' (unknown error)")
                }
            }

            let atom = reply.pointee.atom
            free(reply)

            // Validate atom is non-zero (XCB_ATOM_NONE = 0)
            guard atom != 0 else {
                throw LuminaError.x11ExtensionMissing(extension: "Atom '\(name)' returned XCB_ATOM_NONE")
            }

            atoms.append(atom)
        }

        // Construct atoms struct
        return X11Atoms(
            WM_PROTOCOLS: atoms[0],
            WM_DELETE_WINDOW: atoms[1],
            NET_WM_NAME: atoms[2],
            NET_WM_STATE: atoms[3],
            NET_WM_STATE_ABOVE: atoms[4],
            NET_WM_STATE_FULLSCREEN: atoms[5],
            MOTIF_WM_HINTS: atoms[6],
            CLIPBOARD: atoms[7],
            UTF8_STRING: atoms[8]
        )
    }
}
#endif
