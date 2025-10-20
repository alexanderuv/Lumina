#if os(Linux)
import CXCBLinux
import Glibc  // For free()
import Foundation  // For Data

/// X11 runtime capability detection.
///
/// This module provides runtime detection of X11 features and window manager
/// capabilities. It determines which optional features are supported by the
/// current X server, extensions, and window manager, enabling graceful feature
/// degradation and compatibility reporting.
///
/// Detected capabilities:
/// - EWMH (Extended Window Manager Hints) support level
/// - XInput2 availability for advanced input
/// - XRandR version for monitor management
/// - Window manager compatibility (GNOME, KDE, i3, Openbox, etc.)
/// - Transparency support (ARGB visual)
/// - Always-on-top support (_NET_WM_STATE_ABOVE)
/// - Decoration toggle support (_MOTIF_WM_HINTS)
///
/// Example usage:
/// ```swift
/// let caps = try X11Capabilities.detect(connection: conn, screen: screen)
/// print("EWMH support: \(caps.ewmhSupported)")
/// print("XRandR version: \(caps.xrandrMajor).\(caps.xrandrMinor)")
/// print("Window manager: \(caps.windowManager)")
///
/// let windowCaps = caps.windowCapabilities()
/// if windowCaps.supportsTransparency {
///     try window.setTransparent(true)
/// }
/// ```
@MainActor
public struct X11Capabilities: Sendable {
    /// Whether EWMH (Extended Window Manager Hints) is supported.
    ///
    /// EWMH is a freedesktop.org standard that modern window managers implement
    /// to provide consistent window management APIs. It enables features like:
    /// - Window state management (_NET_WM_STATE)
    /// - Fullscreen support (_NET_WM_STATE_FULLSCREEN)
    /// - Always-on-top (_NET_WM_STATE_ABOVE)
    /// - Window type hints (_NET_WM_WINDOW_TYPE)
    ///
    /// Nearly all modern window managers support EWMH (GNOME, KDE, i3, Openbox, etc.).
    public let ewmhSupported: Bool

    /// EWMH specification version supported by window manager.
    ///
    /// The version string is read from _NET_SUPPORTING_WM_CHECK window.
    /// Example: "GNOME Shell", "KWin", "i3"
    public let ewmhVersion: String?

    /// Whether XInput2 extension is available.
    ///
    /// XInput2 provides advanced input device support including:
    /// - Multi-touch and gesture recognition
    /// - High-precision scrolling (smooth scrolling)
    /// - Pen/tablet input with pressure sensitivity
    /// - Device hot-plugging events
    ///
    /// Most modern systems have XInput2, but it may be absent on very old X servers.
    public let xinput2Available: Bool

    /// XRandR extension major version.
    ///
    /// XRandR (X Resize and Rotate) is required for monitor enumeration and DPI detection.
    /// Minimum required version: 1.2 (released 2006)
    /// Current version: 1.6 (released 2015)
    public let xrandrMajor: UInt32

    /// XRandR extension minor version.
    public let xrandrMinor: UInt32

    /// Detected window manager name.
    ///
    /// Common values:
    /// - "GNOME Shell" (GNOME 3+)
    /// - "Mutter" (GNOME 2, GNOME Flashback)
    /// - "KWin" (KDE Plasma)
    /// - "i3" (i3 tiling window manager)
    /// - "Openbox" (lightweight stacking WM)
    /// - "Xfwm4" (Xfce window manager)
    /// - "Unknown" (cannot detect or no EWMH support)
    public let windowManager: String

    /// Whether ARGB visual (transparency) is available.
    ///
    /// ARGB visuals enable per-pixel alpha transparency for windows.
    /// This is required for custom window shapes, rounded corners, and
    /// translucent effects.
    ///
    /// Availability:
    /// - Generally available on modern compositing window managers
    /// - May be unavailable on lightweight WMs without compositing
    /// - Requires X server support for 32-bit depth visuals
    public let argbVisualAvailable: Bool

    /// Whether the window manager supports _NET_WM_STATE_ABOVE (always-on-top).
    ///
    /// This capability is queried from _NET_SUPPORTED root window property.
    /// If supported, windows can be made always-on-top using the EWMH protocol.
    public let supportsAlwaysOnTop: Bool

    /// Whether Motif WM Hints are supported for decoration control.
    ///
    /// Motif WM Hints (_MOTIF_WM_HINTS) is a legacy but widely-supported
    /// protocol for toggling window decorations (title bar, borders).
    /// Most window managers support this, even if they don't use Motif.
    public let supportsMotifHints: Bool

    // MARK: - Detection

    /// Detect X11 capabilities for the current environment.
    ///
    /// This function queries the X server and window manager to determine
    /// which features are available. It performs these checks:
    /// 1. Query EWMH support via _NET_SUPPORTING_WM_CHECK
    /// 2. Query XInput2 extension via xcb_query_extension
    /// 3. Query XRandR version via xcb_randr_query_version
    /// 4. Detect window manager name via _NET_WM_NAME on supporting window
    /// 5. Check for ARGB visual in screen's visuals list
    /// 6. Query _NET_SUPPORTED for EWMH feature atoms
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - screen: Default screen
    /// - Returns: X11Capabilities struct with detected features
    /// - Throws: LuminaError on critical failures (unlikely)
    ///
    /// Example:
    /// ```swift
    /// let caps = try X11Capabilities.detect(connection: conn, screen: screen)
    /// print("Window manager: \(caps.windowManager)")
    /// print("EWMH: \(caps.ewmhSupported ? "yes" : "no")")
    /// print("ARGB visual: \(caps.argbVisualAvailable ? "yes" : "no")")
    /// ```
    public static func detect(
        connection: OpaquePointer,
        screen: UnsafeMutablePointer<xcb_screen_t>
    ) throws -> X11Capabilities {
        let rootWindow = screen.pointee.root

        // Detect EWMH support
        let ewmhSupported = detectEWMH(connection: connection, rootWindow: rootWindow)

        // Detect window manager name
        let windowManager = detectWindowManager(connection: connection, rootWindow: rootWindow)

        // Detect XInput2
        let xinput2Available = detectXInput2(connection: connection)

        // Detect XRandR version
        let (xrandrMajor, xrandrMinor) = detectXRandR(connection: connection)

        // Detect ARGB visual
        let argbVisualAvailable = detectARGBVisual(screen: screen)

        // Query EWMH supported features
        let supportedAtoms = querySupportedAtoms(connection: connection, rootWindow: rootWindow)
        let supportsAlwaysOnTop = supportedAtoms.contains("_NET_WM_STATE_ABOVE")

        // Motif hints are universally supported (legacy protocol)
        let supportsMotifHints = true

        return X11Capabilities(
            ewmhSupported: ewmhSupported,
            ewmhVersion: nil,  // Not easily queryable
            xinput2Available: xinput2Available,
            xrandrMajor: xrandrMajor,
            xrandrMinor: xrandrMinor,
            windowManager: windowManager,
            argbVisualAvailable: argbVisualAvailable,
            supportsAlwaysOnTop: supportsAlwaysOnTop,
            supportsMotifHints: supportsMotifHints
        )
    }

    // MARK: - Capability Queries

    /// Convert to WindowCapabilities for the Lumina API.
    ///
    /// - Returns: WindowCapabilities struct describing window features
    public func windowCapabilities() -> WindowCapabilities {
        return WindowCapabilities(
            supportsTransparency: argbVisualAvailable,
            supportsAlwaysOnTop: supportsAlwaysOnTop,
            supportsDecorationToggle: supportsMotifHints,
            supportsClientSideDecorations: false  // X11 uses server-side decorations
        )
    }

    /// Convert to MonitorCapabilities for the Lumina API.
    ///
    /// - Returns: MonitorCapabilities struct describing monitor features
    public func monitorCapabilities() -> MonitorCapabilities {
        return MonitorCapabilities(
            supportsDynamicRefreshRate: false,  // Not standard in X11
            supportsFractionalScaling: true     // Via Xft.dpi and application rendering
        )
    }

    /// Convert to ClipboardCapabilities for the Lumina API.
    ///
    /// - Returns: ClipboardCapabilities struct describing clipboard features
    public func clipboardCapabilities() -> ClipboardCapabilities {
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,  // Not implemented in Milestone 1
            supportsHTML: false     // Not implemented in Milestone 1
        )
    }

    // MARK: - Window Manager Compatibility

    /// Get a human-readable compatibility report for the detected window manager.
    ///
    /// This report describes known issues, limitations, and workarounds for
    /// the detected window manager.
    ///
    /// - Returns: Multiline string with compatibility information
    ///
    /// Example:
    /// ```swift
    /// let caps = try X11Capabilities.detect(connection: conn, screen: screen)
    /// print(caps.compatibilityReport())
    /// ```
    public func compatibilityReport() -> String {
        var report = "Window Manager Compatibility Report\n"
        report += "====================================\n\n"
        report += "Detected WM: \(windowManager)\n"
        report += "EWMH Support: \(ewmhSupported ? "✓" : "✗")\n"
        report += "XRandR: \(xrandrMajor).\(xrandrMinor)\n"
        report += "XInput2: \(xinput2Available ? "✓" : "✗")\n"
        report += "ARGB Visual: \(argbVisualAvailable ? "✓" : "✗")\n\n"

        // Window manager-specific notes
        switch windowManager.lowercased() {
        case let wm where wm.contains("gnome"):
            report += "GNOME Shell: Excellent compatibility\n"
            report += "- Full EWMH support\n"
            report += "- Compositing enabled by default\n"
            report += "- All features supported\n"

        case let wm where wm.contains("kwin"):
            report += "KDE KWin: Excellent compatibility\n"
            report += "- Full EWMH support\n"
            report += "- Advanced compositing effects\n"
            report += "- All features supported\n"

        case "i3":
            report += "i3 Window Manager: Good compatibility\n"
            report += "- Tiling WM with EWMH support\n"
            report += "- No compositing (ARGB may not work without compton/picom)\n"
            report += "- Decorations limited (tiling paradigm)\n"

        case let wm where wm.contains("openbox"):
            report += "Openbox: Good compatibility\n"
            report += "- Lightweight stacking WM with EWMH\n"
            report += "- No built-in compositing (requires external compositor)\n"
            report += "- All window features supported\n"

        case let wm where wm.contains("xfwm"):
            report += "Xfwm4 (Xfce): Good compatibility\n"
            report += "- Full EWMH support\n"
            report += "- Built-in compositing (optional)\n"
            report += "- All features supported\n"

        default:
            report += "Unknown/Other Window Manager\n"
            report += "- Compatibility depends on EWMH support\n"
            report += "- Test thoroughly if using advanced features\n"
        }

        return report
    }

    // MARK: - Private Detection Methods

    /// Detect EWMH support via _NET_SUPPORTING_WM_CHECK.
    private static func detectEWMH(connection: OpaquePointer, rootWindow: xcb_window_t) -> Bool {
        // Intern _NET_SUPPORTING_WM_CHECK atom
        let atomCookie = xcb_intern_atom(connection, 1, 24, "_NET_SUPPORTING_WM_CHECK")
        guard let atomReply = xcb_intern_atom_reply(connection, atomCookie, nil) else {
            return false
        }
        let checkAtom = atomReply.pointee.atom
        free(atomReply)

        guard checkAtom != UInt32(XCB_ATOM_NONE.rawValue) else {
            return false
        }

        // Query property on root window
        let propCookie = xcb_get_property(connection, 0, rootWindow, checkAtom, UInt32(XCB_ATOM_WINDOW.rawValue), 0, 1)
        guard let propReply = xcb_get_property_reply(connection, propCookie, nil) else {
            return false
        }
        defer { free(propReply) }

        // If property exists with WINDOW type, EWMH is supported
        return propReply.pointee.type == XCB_ATOM_WINDOW.rawValue && propReply.pointee.format == 32
    }

    /// Detect window manager name via _NET_WM_NAME on supporting window.
    private static func detectWindowManager(connection: OpaquePointer, rootWindow: xcb_window_t) -> String {
        // Intern atoms
        let checkAtomCookie = xcb_intern_atom(connection, 1, 24, "_NET_SUPPORTING_WM_CHECK")
        let nameAtomCookie = xcb_intern_atom(connection, 1, 12, "_NET_WM_NAME")
        let utf8AtomCookie = xcb_intern_atom(connection, 1, 11, "UTF8_STRING")

        guard let checkAtomReply = xcb_intern_atom_reply(connection, checkAtomCookie, nil),
              let nameAtomReply = xcb_intern_atom_reply(connection, nameAtomCookie, nil),
              let utf8AtomReply = xcb_intern_atom_reply(connection, utf8AtomCookie, nil) else {
            return "Unknown"
        }

        let checkAtom = checkAtomReply.pointee.atom
        let nameAtom = nameAtomReply.pointee.atom
        let utf8Atom = utf8AtomReply.pointee.atom

        free(checkAtomReply)
        free(nameAtomReply)
        free(utf8AtomReply)

        // Get supporting WM check window
        let checkPropCookie = xcb_get_property(connection, 0, rootWindow, checkAtom, XCB_ATOM_WINDOW.rawValue, 0, 1)
        guard let checkPropReply = xcb_get_property_reply(connection, checkPropCookie, nil) else {
            return "Unknown"
        }
        defer { free(checkPropReply) }

        guard checkPropReply.pointee.type == XCB_ATOM_WINDOW.rawValue,
              let valuePtr = xcb_get_property_value(checkPropReply) else {
            return "Unknown"
        }

        let supportingWindow = valuePtr.load(as: xcb_window_t.self)

        // Get _NET_WM_NAME from supporting window
        let namePropCookie = xcb_get_property(connection, 0, supportingWindow, nameAtom, utf8Atom, 0, 256)
        guard let namePropReply = xcb_get_property_reply(connection, namePropCookie, nil) else {
            return "Unknown"
        }
        defer { free(namePropReply) }

        let length = Int(xcb_get_property_value_length(namePropReply))
        guard length > 0, let nameValuePtr = xcb_get_property_value(namePropReply) else {
            return "Unknown"
        }

        let data = Data(bytes: nameValuePtr, count: length)
        return String(data: data, encoding: .utf8) ?? "Unknown"
    }

    /// Detect XInput2 extension availability.
    private static func detectXInput2(connection: OpaquePointer) -> Bool {
        let extensionName = "XInputExtension"
        let cookie = xcb_query_extension(connection, UInt16(extensionName.utf8.count), extensionName)
        guard let reply = xcb_query_extension_reply(connection, cookie, nil) else {
            return false
        }
        defer { free(reply) }

        return reply.pointee.present != 0
    }

    /// Detect XRandR extension version.
    private static func detectXRandR(connection: OpaquePointer) -> (major: UInt32, minor: UInt32) {
        // Request XRandR version
        let cookie = xcb_randr_query_version(connection, 1, 6)  // Request v1.6
        guard let reply = xcb_randr_query_version_reply(connection, cookie, nil) else {
            return (0, 0)  // XRandR not available
        }
        defer { free(reply) }

        return (UInt32(reply.pointee.major_version), UInt32(reply.pointee.minor_version))
    }

    /// Detect ARGB visual (32-bit depth with alpha channel).
    private static func detectARGBVisual(screen: UnsafeMutablePointer<xcb_screen_t>) -> Bool {
        // Get depth iterator
        var depthIter = xcb_screen_allowed_depths_iterator(screen)

        while depthIter.rem > 0 {
            guard let depth = depthIter.data else {
                xcb_depth_next(&depthIter)
                continue
            }

            // Check if this is 32-bit depth
            if depth.pointee.depth == 32 {
                // 32-bit depth indicates ARGB visual support
                return true
            }

            xcb_depth_next(&depthIter)
        }

        return false
    }

    /// Query _NET_SUPPORTED atoms from root window.
    private static func querySupportedAtoms(connection: OpaquePointer, rootWindow: xcb_window_t) -> Set<String> {
        // Intern _NET_SUPPORTED atom
        let atomCookie = xcb_intern_atom(connection, 1, 14, "_NET_SUPPORTED")
        guard let atomReply = xcb_intern_atom_reply(connection, atomCookie, nil) else {
            return []
        }
        let supportedAtom = atomReply.pointee.atom
        free(atomReply)

        guard supportedAtom != XCB_ATOM_NONE.rawValue else {
            return []
        }

        // Query property
        let propCookie = xcb_get_property(connection, 0, rootWindow, supportedAtom, XCB_ATOM_ATOM.rawValue, 0, 1024)
        guard let propReply = xcb_get_property_reply(connection, propCookie, nil) else {
            return []
        }
        defer { free(propReply) }

        let atomCount = Int(xcb_get_property_value_length(propReply)) / MemoryLayout<xcb_atom_t>.size
        guard let atomsPtr = xcb_get_property_value(propReply)?.assumingMemoryBound(to: xcb_atom_t.self) else {
            return []
        }

        // Convert atoms to string names
        var atomNames = Set<String>()
        for i in 0..<atomCount {
            let atom = atomsPtr[i]

            // Get atom name
            let nameCookie = xcb_get_atom_name(connection, atom)
            guard let nameReply = xcb_get_atom_name_reply(connection, nameCookie, nil) else {
                continue
            }
            defer { free(nameReply) }

            let nameLength = Int(xcb_get_atom_name_name_length(nameReply))
            guard let namePtr = xcb_get_atom_name_name(nameReply) else {
                continue
            }

            let data = Data(bytes: namePtr, count: nameLength)
            if let name = String(data: data, encoding: .utf8) {
                atomNames.insert(name)
            }
        }

        return atomNames
    }
}

#endif
