#if os(Linux) && LUMINA_WAYLAND

import Foundation
import CWaylandClient

/// Wayland platform implementation.
///
/// WaylandPlatform manages the wl_display connection and provides platform-level
/// operations like monitor enumeration that don't require an application event loop.
///
/// **Architecture:**
/// - Platform owns the wl_display connection
/// - Platform owns the WaylandMonitorTracker
/// - Platform can be initialized without creating an app
/// - Only one app can be created per platform instance
/// - App holds a strong reference to platform for lifetime management
///
/// **Usage:**
/// ```swift
/// // Initialize platform
/// let platform = try WaylandPlatform()
///
/// // Query monitors (no app needed!)
/// let monitors = try platform.enumerateMonitors()
///
/// // Create app when ready
/// let app = try platform.createApp()
/// ```
@MainActor
public final class WaylandPlatform: LuminaPlatform {
    // MARK: - State

    /// Wayland display connection (owned by platform)
    /// **Concurrency:** nonisolated(unsafe) allows access from deinit (which is nonisolated).
    /// This is safe because deinit runs when no other code can access the object.
    private nonisolated(unsafe) let display: OpaquePointer

    /// Monitor tracker (owned by platform)
    private let monitorTracker: WaylandMonitorTracker

    /// Registry for global bindings
    /// **Concurrency:** nonisolated(unsafe) allows access from deinit (which is nonisolated).
    /// This is safe because deinit runs when no other code can access the object.
    private nonisolated(unsafe) var registry: OpaquePointer?

    /// Track if app has been created (only one allowed)
    private var appCreated: Bool = false

    /// Logger
    private let logger: LuminaLogger

    /// Context for registry callbacks
    private var registryContext: RegistryContext?

    // MARK: - Initialization

    public init() throws {
        logger = LuminaLogger(label: "com.lumina.wayland.platform", level: .info)
        logger.logEvent("Initializing Wayland platform")

        // Connect to Wayland display
        guard let display = wl_display_connect(nil) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "Display connection",
                code: -1,
                message: "Failed to connect to Wayland display. Is WAYLAND_DISPLAY set?"
            )
        }
        self.display = display
        logger.logPlatformCall("wl_display_connect() -> \(display)")

        // Get registry
        guard let registry = wl_display_get_registry(display) else {
            wl_display_disconnect(display)
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "Registry creation",
                code: -1,
                message: "Failed to get wl_registry"
            )
        }
        self.registry = registry
        logger.logPlatformCall("wl_display_get_registry() -> \(registry)")

        // Initialize monitor tracker
        self.monitorTracker = WaylandMonitorTracker(display: display)
        logger.logEvent("Monitor tracker initialized")

        // Set up registry listener for wl_output globals
        let context = RegistryContext(monitorTracker: monitorTracker)
        self.registryContext = context

        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        var registryListener = wl_registry_listener(
            global: registryGlobalCallback,
            global_remove: registryGlobalRemoveCallback
        )
        wl_registry_add_listener(registry, &registryListener, contextPtr)
        logger.logPlatformCall("wl_registry_add_listener()")

        // Roundtrip to bind all globals (especially wl_output for monitors)
        wl_display_roundtrip(display)
        logger.logPlatformCall("wl_display_roundtrip() - discovered globals")

        // Second roundtrip to process initial events from wl_output
        wl_display_roundtrip(display)
        logger.logPlatformCall("wl_display_roundtrip() - processed initial events")

        logger.logEvent("Wayland platform initialized successfully")
    }

    // MARK: - Monitor Enumeration

    public func enumerateMonitors() throws -> [Monitor] {
        try monitorTracker.enumerateMonitors()
    }

    public func primaryMonitor() throws -> Monitor {
        try monitorTracker.primaryMonitor()
    }

    // MARK: - App Creation

    public func createApp() throws -> any LuminaApp {
        guard !appCreated else {
            throw LuminaError.invalidState(
                "Application already created. Only one app per platform instance is allowed."
            )
        }

        appCreated = true
        logger.logEvent("Creating Wayland application")

        return try WaylandApplication(platform: self)
    }

    // MARK: - Capabilities

    public static func monitorCapabilities() -> MonitorCapabilities {
        MonitorCapabilities(
            supportsDynamicRefreshRate: false,
            supportsFractionalScaling: false
        )
    }

    public static func clipboardCapabilities() -> ClipboardCapabilities {
        ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,
            supportsHTML: false
        )
    }

    // MARK: - Internal Access (for WaylandApplication)

    /// Access display connection (internal, read-only)
    ///
    /// WaylandApplication needs the display connection for window creation
    /// and event loop management. This property provides controlled access
    /// without exposing the private display field publicly.
    internal var displayConnection: OpaquePointer { display }

    /// Access monitor tracker (internal, read-only)
    ///
    /// WaylandApplication may need direct access to the monitor tracker
    /// for monitor-related functionality.
    internal var monitors: WaylandMonitorTracker { monitorTracker }

    // MARK: - Cleanup

    deinit {
        logger.logEvent("Cleaning up Wayland platform")
        if let registry = registry {
            wl_registry_destroy(registry)
        }
        wl_display_disconnect(display)
    }
}

// MARK: - Registry Context

/// Context object for registry callbacks.
///
/// This class holds weak references to the monitor tracker and allows
/// C callbacks to access Swift state safely.
private final class RegistryContext {
    weak var monitorTracker: WaylandMonitorTracker?

    init(monitorTracker: WaylandMonitorTracker) {
        self.monitorTracker = monitorTracker
    }
}

// MARK: - Registry Callbacks

/// C callback for wl_registry.global events
///
/// Called when the Wayland compositor announces global interfaces.
/// We bind to wl_output globals for monitor enumeration.
private func registryGlobalCallback(
    userData: UnsafeMutableRawPointer?,
    registry: OpaquePointer?,
    name: UInt32,
    interface: UnsafePointer<CChar>?,
    version: UInt32
) {
    guard let userData = userData, let interface = interface, let registry = registry else { return }
    let context = Unmanaged<RegistryContext>.fromOpaque(userData).takeUnretainedValue()
    let interfaceName = String(cString: interface)

    // We only care about wl_output for monitor enumeration
    // Other globals (compositor, shm, seat, etc.) are handled by WaylandApplication
    if interfaceName == "wl_output" {
        context.monitorTracker?.bindOutput(registry: registry, name: name, version: version)
    }
}

/// C callback for wl_registry.global_remove events
///
/// Called when a global interface is removed (e.g., monitor disconnected).
private func registryGlobalRemoveCallback(
    userData: UnsafeMutableRawPointer?,
    registry: OpaquePointer?,
    name: UInt32
) {
    guard let userData = userData else { return }
    let context = Unmanaged<RegistryContext>.fromOpaque(userData).takeUnretainedValue()

    // Notify monitor tracker of output removal
    context.monitorTracker?.removeOutput(name: name)
}

#endif // os(Linux) && LUMINA_WAYLAND
