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
/// This design matches SDL/GLFW's pattern where you initialize the library before
/// creating windows and running the event loop.
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

/// Create a new Lumina platform instance.
///
/// This factory method automatically selects the correct platform implementation
/// based on the operating system and available display servers.
///
/// **Platform Selection:**
/// - **macOS**: Returns MacPlatform (AppKit-based)
/// - **Windows**: Returns WinPlatform (Win32-based)
/// - **Linux**: Returns WaylandPlatform or X11Platform based on environment detection
///
/// On Linux, the platform is selected automatically:
/// - If `WAYLAND_DISPLAY` is set: Try Wayland, fall back to X11 on failure
/// - If `DISPLAY` is set: Use X11
/// - If neither: Throw error (no display server detected)
///
/// Example:
/// ```swift
/// let platform = try createLuminaPlatform()
/// let monitors = try platform.enumerateMonitors()
/// var app = try platform.createApp()
/// ```
///
/// - Throws: `LuminaError.platformError` if platform initialization fails
/// - Returns: A new platform instance ready to enumerate monitors and create apps
@MainActor
public func createLuminaPlatform() throws -> any LuminaPlatform {
    #if os(macOS)
    return try MacPlatform()
    #elseif os(Windows)
    return try WinPlatform()
    #elseif os(Linux)
    return try createLinuxPlatform(.auto)
    #else
    #error("Unsupported platform")
    #endif
}
