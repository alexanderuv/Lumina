#if os(Windows)

import Foundation
import WinSDK

/// Windows platform implementation.
///
/// WinPlatform provides platform-level operations for Windows, including monitor
/// enumeration and application creation. Unlike Wayland/X11, Windows doesn't require
/// an explicit display connection since Win32 APIs are always available.
///
/// **Architecture:**
/// - Platform doesn't manage any connection (Win32 APIs are globally available)
/// - Platform can be initialized without creating an app
/// - Only one app can be created per platform instance
/// - App holds a strong reference to platform for lifetime management
///
/// **Usage:**
/// ```swift
/// // Initialize platform
/// let platform = try WinPlatform()
///
/// // Query monitors (no app needed!)
/// let monitors = try platform.enumerateMonitors()
///
/// // Create app when ready
/// let app = try platform.createApp()
/// ```
@MainActor
public final class WinPlatform: LuminaPlatform {
    // MARK: - Shared Instance

    /// Shared platform instance for WndProc access (static C callback)
    /// Only one platform exists per process
    static var shared: WinPlatform?

    // MARK: - State

    /// Track if app has been created (only one allowed)
    private var appCreated: Bool = false

    /// Logger
    private let logger: LuminaLogger

    /// Strong reference to the app (platform owns the app)
    /// WndProc needs to post events to the app's event queue
    var app: WinApplication?

    // MARK: - Initialization

    public init() throws {
        logger = LuminaLogger(label: "com.lumina.windows.platform", level: .info)
        logger.info("Initializing Windows platform")

        // Windows doesn't require explicit platform connection
        // Win32 APIs are globally available
        logger.info("Windows platform initialized successfully")

        // Register as shared instance for WndProc access
        WinPlatform.shared = self
    }

    // MARK: - Monitor Enumeration

    public func enumerateMonitors() throws -> [Monitor] {
        try WinMonitor.enumerateMonitors()
    }

    public func primaryMonitor() throws -> Monitor {
        try WinMonitor.primaryMonitor()
    }

    // MARK: - App Creation

    public func createApp() throws -> any LuminaApp {
        guard !appCreated else {
            throw LuminaError.invalidState(
                "Application already created. Only one app per platform instance is allowed."
            )
        }

        appCreated = true
        logger.info("Creating Windows application")

        return try WinApplication(platform: self)
    }

    // MARK: - Capabilities

    public static func monitorCapabilities() -> MonitorCapabilities {
        // Windows supports per-monitor DPI scaling (Windows 10+)
        // Dynamic refresh rate support depends on hardware and Windows 11
        let logger = LuminaLogger(label: "com.lumina.windows", level: .debug)
        logger.debug("Monitor capabilities: dynamic refresh rate = false, fractional scaling = true (Per-Monitor DPI)")
        return MonitorCapabilities(
            supportsDynamicRefreshRate: false,  // Not universally supported
            supportsFractionalScaling: true      // Per-Monitor DPI awareness
        )
    }

    public static func clipboardCapabilities() -> ClipboardCapabilities {
        // Windows supports text clipboard via Win32 API
        // Images and HTML support is future work
        let logger = LuminaLogger(label: "com.lumina.windows", level: .debug)
        logger.debug("Clipboard capabilities: text = true, images = false, HTML = false")
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,
            supportsHTML: false
        )
    }
}

#endif
