/// Protocol for Lumina platform initialization and management.
///
/// LuminaPlatform represents the underlying platform connection (Wayland display,
/// X11 connection, etc.) and provides platform-level operations that don't require
/// an application event loop.
///
/// **Separation of Concerns:**
/// - **LuminaPlatform**: Platform connection, monitor enumeration (exists independently)
/// - **LuminaApp**: Event loop, window management (requires running process)
///
/// This design separates platform initialization from the application event loop,
/// allowing platform-level operations before creating windows.
///
/// Example usage:
/// ```swift
/// // Step 1: Initialize platform (establishes platform connection)
/// let platform = try createLuminaPlatform()
///
/// // Step 2: Query monitors (platform-level operation, no app needed)
/// let monitors = try platform.enumerateMonitors()
/// let primary = try platform.primaryMonitor()
///
/// // Step 3: Create application (only one per platform)
/// var app = try platform.createApp()
///
/// // Step 4: Create windows and run event loop
/// var window = try app.createWindow(
///     title: "Hello, Lumina!",
///     size: LogicalSize(width: 800, height: 600),
///     resizable: true,
///     monitor: primary
/// )
/// try app.run()
/// ```
///
/// **Platform Lifecycle:**
/// - Platform initialization establishes the platform connection
/// - Platform outlives the application
/// - Only one application can be created per platform instance
/// - Monitor enumeration works before app creation
///
/// Thread Safety: All methods must be called from the main thread (@MainActor).
@MainActor
public protocol LuminaPlatform: AnyObject {
    /// Initialize the platform connection.
    ///
    /// This establishes the underlying platform connection:
    /// - **Wayland**: Connects to wl_display and binds to wl_registry
    /// - **X11**: Opens XDisplay connection
    /// - **macOS**: No connection needed (uses NSScreen directly)
    /// - **Windows**: No connection needed (uses Win32 APIs directly)
    ///
    /// - Throws: `LuminaError.platformError` if platform initialization fails
    init() throws

    /// Enumerate all connected monitors.
    ///
    /// Returns information about all displays connected to the system,
    /// including their position, size, scale factor, and primary status.
    ///
    /// This is a platform-level operation that works before creating an app.
    ///
    /// Example:
    /// ```swift
    /// let platform = try createLuminaPlatform()
    /// let monitors = try platform.enumerateMonitors()
    /// for monitor in monitors {
    ///     print("\(monitor.name): \(monitor.size.width)×\(monitor.size.height)")
    /// }
    /// ```
    ///
    /// - Returns: Array of all detected monitors
    /// - Throws: LuminaError if monitor enumeration fails
    func enumerateMonitors() throws -> [Monitor]

    /// Get the primary monitor.
    ///
    /// Returns the system's primary display, which is typically where new
    /// windows appear by default and where the menu bar/taskbar is located.
    ///
    /// Example:
    /// ```swift
    /// let platform = try createLuminaPlatform()
    /// let primary = try platform.primaryMonitor()
    /// print("Primary: \(primary.name)")
    /// ```
    ///
    /// - Returns: The primary monitor
    /// - Throws: LuminaError if no primary monitor is found
    func primaryMonitor() throws -> Monitor

    /// Create the application instance.
    ///
    /// Creates a LuminaApp that manages the event loop and windows.
    /// The app holds a strong reference to this platform for its lifetime.
    ///
    /// **Important:** Can only be called once per platform instance.
    /// Attempting to create a second app will throw an error.
    ///
    /// Example:
    /// ```swift
    /// var platform = try createLuminaPlatform()
    /// let app = try platform.createApp()  // ✅ OK
    /// try app.run()
    ///
    /// let app2 = try platform.createApp()  // ❌ Throws error
    /// ```
    ///
    /// - Returns: A new application instance
    /// - Throws: LuminaError.invalidState if app already created
    func createApp() throws -> any LuminaApp

    /// Query monitor capabilities for the current platform.
    ///
    /// Returns information about which monitor-related features are supported,
    /// such as dynamic refresh rates (ProMotion) or fractional DPI scaling.
    ///
    /// - Returns: MonitorCapabilities struct describing platform support
    static func monitorCapabilities() -> MonitorCapabilities

    /// Query clipboard capabilities for the current platform.
    ///
    /// Returns information about which clipboard data types are supported
    /// on this platform (text, images, HTML, etc.).
    ///
    /// - Returns: ClipboardCapabilities struct describing platform support
    static func clipboardCapabilities() -> ClipboardCapabilities
}

// MARK: - Platform Factory

#if os(macOS)
/// Create a new Lumina platform instance for macOS.
///
/// Returns a MacPlatform instance using AppKit.
///
/// Example:
/// ```swift
/// let platform = try createLuminaPlatform()
/// let monitors = try platform.enumerateMonitors()
/// var app = try platform.createApp()
/// ```
///
/// - Throws: `LuminaError.platformError` if platform initialization fails
/// - Returns: A new macOS platform instance
@MainActor
public func createLuminaPlatform() throws -> any LuminaPlatform {
    return try MacPlatform()
}

#elseif os(Windows)
/// Create a new Lumina platform instance for Windows.
///
/// Returns a WinPlatform instance using Win32 APIs.
///
/// Example:
/// ```swift
/// let platform = try createLuminaPlatform()
/// let monitors = try platform.enumerateMonitors()
/// var app = try platform.createApp()
/// ```
///
/// - Throws: `LuminaError.platformError` if platform initialization fails
/// - Returns: A new Windows platform instance
@MainActor
public func createLuminaPlatform() throws -> any LuminaPlatform {
    return try WinPlatform()
}

#elseif os(Linux)
import Foundation

/// Logger for Linux platform selection
private let logger = LuminaLogger(label: "lumina.linux", level: .info)

/// Create a new Lumina platform instance for Linux.
///
/// This factory method selects the appropriate Linux display server backend based on
/// the backend parameter. Linux supports multiple display servers:
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
/// - Wayland backend requires `--traits Wayland` build flag
/// - X11 backend is always available on Linux
///
/// Example:
/// ```swift
/// // Automatic backend selection
/// let platform = try createLuminaPlatform()
///
/// // Force Wayland backend
/// let waylandPlatform = try createLuminaPlatform(.wayland)
///
/// // Force X11 backend
/// let x11Platform = try createLuminaPlatform(.x11)
/// ```
///
/// - Parameter backend: The display server backend to use (default: .auto)
/// - Throws: `LuminaError.platformError` if platform initialization fails
/// - Returns: A new Linux platform instance (WaylandPlatform or X11Platform)
@MainActor
public func createLuminaPlatform(_ backend: LinuxBackend = .auto) throws -> any LuminaPlatform {
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
            message: "Wayland backend not compiled. Build with --traits Wayland"
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
                logger.error("Wayland initialization failed: \(error)")
                logger.info("Falling back to X11")
                return try X11Platform()
            }
        }
        #endif

        // Default to X11
        return try X11Platform()
    }
}

#else
#error("Unsupported platform")
#endif
