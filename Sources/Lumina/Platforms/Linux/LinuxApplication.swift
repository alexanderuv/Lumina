#if os(Linux)
import Foundation

/// Linux display server backend selection.
///
/// This enum allows users to control which Linux display server backend to use:
/// - `.auto`: Automatically detect based on environment variables (Wayland → X11 fallback)
/// - `.x11`: Force X11 backend
/// - `.wayland`: Force Wayland backend (requires LUMINA_WAYLAND compile flag)
///
/// Example:
/// ```swift
/// // Auto-detect (default)
/// let app = try createLuminaApp()
///
/// // Force X11
/// let app = try createLuminaApp(.x11)
///
/// #if LUMINA_WAYLAND
/// // Force Wayland
/// let app = try createLuminaApp(.wayland)
/// #endif
/// ```
public enum LinuxBackend {
    /// Automatically detect display server from environment variables.
    /// Prefers Wayland if WAYLAND_DISPLAY is set, falls back to X11 if DISPLAY is set.
    case auto

    /// Force X11 backend, regardless of environment variables.
    case x11

    #if LUMINA_WAYLAND
    /// Force Wayland backend, regardless of environment variables.
    /// Requires Lumina to be compiled with LUMINA_WAYLAND flag.
    case wayland
    #endif
}

/// Create a Linux-specific Lumina application with optional backend selection.
///
/// This factory function detects the available display server (Wayland or X11)
/// using environment variables and returns the appropriate backend implementation.
/// Users can optionally force a specific backend for testing or compatibility.
///
/// **Backend Selection:**
/// - `.auto` (default): Automatic detection based on environment variables
///   1. If `WAYLAND_DISPLAY` is set → Attempt WaylandApplication with X11 fallback
///   2. If `DISPLAY` is set → Use X11Application
///   3. If neither is set → Throw error
/// - `.x11`: Force X11 backend
/// - `.wayland`: Force Wayland backend (requires LUMINA_WAYLAND compile flag)
///
/// **Wayland Priority Rationale:**
/// Modern Linux distributions (GNOME, KDE Plasma) default to Wayland when available.
/// Checking `WAYLAND_DISPLAY` first allows us to use the native Wayland backend,
/// which provides better support for:
/// - Client-side decorations (CSD)
/// - Window transparency
/// - Fractional scaling
/// - Touchpad gestures
///
/// **Use Cases for Explicit Backend:**
/// - Testing: Force X11 on a Wayland system for compatibility testing
/// - Performance: Force Wayland for better performance on supported compositors
/// - Debugging: Isolate backend-specific issues
/// - User preference: Allow users to choose their preferred backend
///
/// Example:
/// ```swift
/// // Automatic backend detection (default)
/// var app = try createLuminaApp()
///
/// // Force X11 backend (even on Wayland system)
/// var app = try createLuminaApp(.x11)
///
/// #if LUMINA_WAYLAND
/// // Force Wayland backend
/// var app = try createLuminaApp(.wayland)
/// #endif
/// ```
///
/// Error Conditions:
/// - Throws `LuminaError.platformError` if no display server is detected (auto mode)
/// - Throws `LuminaError.platformError` if the requested backend is unavailable
/// - Throws `LuminaError.platformError` if `.wayland` is requested but LUMINA_WAYLAND is not compiled
/// - Throws `LuminaError.waylandProtocolMissing` if Wayland compositor lacks required protocols
/// - Throws `LuminaError.x11ExtensionMissing` if X11 server lacks required extensions
///
/// Environment Variables (auto mode):
/// - `WAYLAND_DISPLAY`: Set by Wayland compositors (typically "wayland-0" or "wayland-1")
/// - `DISPLAY`: Set by X11 servers (typically ":0", ":1", etc.)
///
/// - Parameter backend: The display server backend to use (default: .auto)
/// - Returns: A LuminaApp instance backed by the requested or detected backend
/// - Throws: LuminaError if the backend is unavailable or initialization fails
@MainActor
public func createLuminaApp(_ backend: LinuxBackend = .auto) throws -> any LuminaApp {
    let environment = ProcessInfo.processInfo.environment

    // Handle .auto by inlining detection logic
    if case .auto = backend {
        #if LUMINA_WAYLAND
        // Wayland support is compiled in, check for Wayland display server
        if let waylandDisplay = environment["WAYLAND_DISPLAY"], !waylandDisplay.isEmpty {
            // WAYLAND_DISPLAY is set, attempt to use Wayland backend
            do {
                return try WaylandApplication()
            } catch {
                // Wayland initialization failed, try X11 fallback
                if let x11Display = environment["DISPLAY"], !x11Display.isEmpty {
                    return try X11Application()
                } else {
                    // No X11 fallback available, propagate Wayland error
                    throw error
                }
            }
        }
        #endif

        // Check for X11 display server
        if let x11Display = environment["DISPLAY"], !x11Display.isEmpty {
            return try X11Application()
        }

        // No display server detected
        #if LUMINA_WAYLAND
        let message = "No display server detected. Please ensure either WAYLAND_DISPLAY or DISPLAY environment variable is set. Are you running in a graphical session?"
        #else
        let message = "No X11 display server detected. Please ensure DISPLAY environment variable is set. (Note: Wayland support not compiled - rebuild with -Xswiftc -DLUMINA_WAYLAND if needed)"
        #endif

        throw LuminaError.platformError(
            platform: "Linux",
            operation: "createLuminaApp",
            code: -1,
            message: message
        )
    }

    // Handle explicit X11
    if case .x11 = backend {
        return try X11Application()
    }

    #if LUMINA_WAYLAND
    // Handle explicit Wayland (only reachable when LUMINA_WAYLAND is defined)
    return try WaylandApplication()
    #else
    // Unreachable when LUMINA_WAYLAND is not defined (enum only has .auto and .x11)
    fatalError("Unreachable: All LinuxBackend cases should be handled")
    #endif
}

#endif // os(Linux)
