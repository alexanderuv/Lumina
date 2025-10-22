#if os(Linux)

import Foundation
import CXCBLinux

/// X11 platform implementation.
///
/// X11Platform manages the XCB connection and provides platform-level operations
/// like monitor enumeration that don't require an application event loop.
///
/// **Architecture:**
/// - Platform owns the XCB connection (xcb_connection_t)
/// - Platform owns the screen reference
/// - Platform can be initialized without creating an app
/// - Only one app can be created per platform instance
/// - App holds a strong reference to platform for lifetime management
///
/// **Usage:**
/// ```swift
/// // Initialize platform
/// let platform = try X11Platform()
///
/// // Query monitors (no app needed!)
/// let monitors = try platform.enumerateMonitors()
///
/// // Create app when ready
/// let app = try platform.createApp()
/// ```
@MainActor
public final class X11Platform: LuminaPlatform {
    // MARK: - State

    /// XCB connection (owned by platform)
    /// **Concurrency:** nonisolated(unsafe) allows access from deinit (which is nonisolated).
    /// This is safe because deinit runs when no other code can access the object.
    private nonisolated(unsafe) let connection: OpaquePointer

    /// Default screen
    private let screen: UnsafeMutablePointer<xcb_screen_t>

    /// Screen number
    private let screenNumber: Int32

    /// Track if app has been created (only one allowed)
    private var appCreated: Bool = false

    /// Logger
    private let logger: LuminaLogger

    // MARK: - Initialization

    public init() throws {
        logger = LuminaLogger(label: "com.lumina.x11.platform", level: .info)
        logger.logEvent("Initializing X11 platform")

        // Connect to X server (DISPLAY environment variable)
        var screenNum: Int32 = 0
        logger.logPlatformCall("xcb_connect()")
        guard let conn = xcb_connect(nil, &screenNum) else {
            throw LuminaError.platformError(
                platform: "X11",
                operation: "Display connection",
                code: -1,
                message: "Failed to connect to X server. Is DISPLAY set?"
            )
        }

        // Check for connection errors
        let connectionError = xcb_connection_has_error_shim(conn)
        guard connectionError == 0 else {
            xcb_disconnect(conn)
            throw LuminaError.platformError(
                platform: "X11",
                operation: "Display connection",
                code: Int(connectionError),
                message: "XCB connection error: \(connectionError)"
            )
        }

        self.connection = conn
        self.screenNumber = screenNum
        logger.logPlatformCall("xcb_connect() -> screen \(screenNum)")

        // Get setup and screen
        logger.logPlatformCall("xcb_get_setup()")
        guard let setup = xcb_get_setup_shim(conn) else {
            xcb_disconnect(conn)
            throw LuminaError.platformError(
                platform: "X11",
                operation: "Screen setup",
                code: -1,
                message: "Failed to get X11 setup"
            )
        }

        var screenIter = xcb_setup_roots_iterator_shim(setup)
        for _ in 0..<screenNum {
            xcb_screen_next(&screenIter)
        }

        guard let screen = screenIter.data else {
            xcb_disconnect(conn)
            throw LuminaError.platformError(
                platform: "X11",
                operation: "Screen setup",
                code: -1,
                message: "Failed to get default screen"
            )
        }

        self.screen = screen
        logger.logEvent("X11 platform initialized successfully")
    }

    // MARK: - Monitor Enumeration

    public func enumerateMonitors() throws -> [Monitor] {
        try X11Monitor.enumerateMonitors(connection: connection, screen: screen)
    }

    public func primaryMonitor() throws -> Monitor {
        try X11Monitor.primaryMonitor(connection: connection, screen: screen)
    }

    // MARK: - App Creation

    public func createApp() throws -> any LuminaApp {
        guard !appCreated else {
            throw LuminaError.invalidState(
                "Application already created. Only one app per platform instance is allowed."
            )
        }

        appCreated = true
        logger.logEvent("Creating X11 application")

        return try X11Application(platform: self)
    }

    // MARK: - Capabilities

    public static func monitorCapabilities() -> MonitorCapabilities {
        MonitorCapabilities(
            supportsDynamicRefreshRate: false,
            supportsFractionalScaling: true  // Via Xft.dpi
        )
    }

    public static func clipboardCapabilities() -> ClipboardCapabilities {
        ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,
            supportsHTML: false
        )
    }

    // MARK: - Internal Access (for X11Application)

    /// Access XCB connection (internal, read-only)
    ///
    /// X11Application needs the connection for window creation and event loop management.
    /// This property provides controlled access without exposing the private connection field publicly.
    internal var xcbConnection: OpaquePointer { connection }

    /// Access screen (internal, read-only)
    ///
    /// X11Application needs the screen for window creation.
    internal var xcbScreen: UnsafeMutablePointer<xcb_screen_t> { screen }

    /// Screen number (internal, read-only)
    internal var xcbScreenNumber: Int32 { screenNumber }

    // MARK: - Cleanup

    deinit {
        logger.logEvent("Cleaning up X11 platform")
        xcb_disconnect(connection)
    }
}

#endif // os(Linux)
