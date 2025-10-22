#if os(Linux)

import Foundation

/// Linux platform backend selection.
///
/// Linux supports multiple display server protocols (Wayland and X11).
/// This enum allows selecting which backend to use.
public enum LinuxBackend {
    /// Use Wayland protocol (requires LUMINA_WAYLAND build flag)
    case wayland

    /// Use X11 protocol
    case x11

    /// Automatic detection: try Wayland first if WAYLAND_DISPLAY is set, fall back to X11
    case auto
}

/// Create Linux platform with specified backend.
///
/// This function selects the appropriate Linux display server backend based on
/// the LinuxBackend parameter. On Linux systems, you can choose between:
///
/// - **Wayland**: Modern protocol with better security and performance
/// - **X11**: Traditional X Window System with broader compatibility
/// - **auto**: Automatic selection based on environment variables
///
/// **Backend Selection Logic (auto mode):**
/// 1. If `WAYLAND_DISPLAY` environment variable is set and Wayland support is compiled in:
///    Try to initialize WaylandPlatform. If it fails, fall back to X11.
/// 2. Otherwise: Use X11Platform
///
/// **Build Requirements:**
/// - Wayland backend requires `-DLUMINA_WAYLAND` compiler flag
/// - X11 backend is always available on Linux
///
/// Example usage:
/// ```swift
/// // Automatic backend selection
/// let platform = try createLinuxPlatform(.auto)
///
/// // Force specific backend
/// let waylandPlatform = try createLinuxPlatform(.wayland)
/// let x11Platform = try createLinuxPlatform(.x11)
/// ```
///
/// - Parameter backend: The display server backend to use (default: .auto)
/// - Returns: A LuminaPlatform implementation (WaylandPlatform or X11Platform)
/// - Throws: LuminaError.platformError if the selected backend cannot be initialized
@MainActor
public func createLinuxPlatform(_ backend: LinuxBackend = .auto) throws -> any LuminaPlatform {
    switch backend {
    #if LUMINA_WAYLAND
    case .wayland:
        return try WaylandPlatform()
    #else
    case .wayland:
        throw LuminaError.platformError(
            platform: "Linux",
            operation: "Wayland backend selection",
            code: -1,
            message: "Wayland backend not compiled. Build with -Xcc -DLUMINA_WAYLAND"
        )
    #endif

    case .x11:
        return try X11Platform()

    case .auto:
        #if LUMINA_WAYLAND
        // Try Wayland first if WAYLAND_DISPLAY is set
        if ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil {
            do {
                return try WaylandPlatform()
            } catch {
                // Wayland failed, fall back to X11
                // Log the failure but continue with X11
                print("[Lumina] Wayland initialization failed: \(error)")
                print("[Lumina] Falling back to X11")
                return try X11Platform()
            }
        }
        #endif

        // Default to X11
        return try X11Platform()
    }
}

#endif // os(Linux)
