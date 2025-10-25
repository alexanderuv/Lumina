#if os(macOS)

import Foundation

/// macOS platform implementation.
///
/// MacPlatform provides platform-level operations for macOS, including monitor
/// enumeration and application creation. Unlike Wayland/X11, macOS doesn't require
/// an explicit display connection since NSScreen APIs are always available.
///
/// **Architecture:**
/// - Platform doesn't manage any connection (NSScreen APIs are globally available)
/// - Platform can be initialized without creating an app
/// - Only one app can be created per platform instance
/// - App holds a strong reference to platform for lifetime management
///
/// **Usage:**
/// ```swift
/// // Initialize platform
/// let platform = try MacPlatform()
///
/// // Query monitors (no app needed!)
/// let monitors = try platform.enumerateMonitors()
///
/// // Create app when ready
/// let app = try platform.createApp()
/// ```
@MainActor
public final class MacPlatform: LuminaPlatform {
    // MARK: - State

    /// Track if app has been created (only one allowed)
    private var appCreated: Bool = false

    /// Logger
    private let logger: LuminaLogger

    // MARK: - Initialization

    public init() throws {
        logger = LuminaLogger(label: "com.lumina.macos.platform", level: .info)
        logger.logEvent("Initializing macOS platform")

        // macOS doesn't require explicit platform connection
        // NSScreen and NSApplication APIs are globally available
        logger.logEvent("macOS platform initialized successfully")
    }

    // MARK: - Monitor Enumeration

    public func enumerateMonitors() throws -> [Monitor] {
        try MacMonitor.enumerateMonitors()
    }

    public func primaryMonitor() throws -> Monitor {
        try MacMonitor.primaryMonitor()
    }

    // MARK: - App Creation

    public func createApp() throws -> any LuminaApp {
        guard !appCreated else {
            throw LuminaError.invalidState(
                "Application already created. Only one app per platform instance is allowed."
            )
        }

        appCreated = true
        logger.logEvent("Creating macOS application")

        return try MacApplication(platform: self)
    }

    // MARK: - Capabilities

    public static func monitorCapabilities() -> MonitorCapabilities {
        // macOS supports ProMotion (dynamic refresh rate) on newer MacBook Pros
        // and Studio Display. Also supports fractional scaling through Retina modes.
        let logger = LuminaLogger(label: "com.lumina.macos", level: .debug)
        logger.logCapabilityDetection("Monitor capabilities: dynamic refresh rate = true (ProMotion), fractional scaling = true (Retina)")
        return MonitorCapabilities(
            supportsDynamicRefreshRate: true,  // ProMotion on supported hardware
            supportsFractionalScaling: true     // Retina scaling modes
        )
    }

    public static func clipboardCapabilities() -> ClipboardCapabilities {
        // macOS supports text clipboard via NSPasteboard
        // Images and HTML support is future work
        let logger = LuminaLogger(label: "com.lumina.macos", level: .debug)
        logger.logCapabilityDetection("Clipboard capabilities: text = true, images = false, HTML = false")
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,
            supportsHTML: false
        )
    }
}

#endif
