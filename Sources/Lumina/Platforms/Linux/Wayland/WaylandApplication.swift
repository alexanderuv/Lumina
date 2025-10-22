#if os(Linux) && LUMINA_WAYLAND
import Foundation
import CWaylandClient

/// Wayland implementation of LuminaApp using libdecor for window decorations.
///
/// Architecture:
/// - Display connection via wl_display_connect()
/// - libdecor context for automatic SSD/CSD decoration handling
/// - wl_seat for input device management
/// - Event loop: libdecor_dispatch → wl_display_dispatch → wl_display_flush
///
/// Thread Safety: All methods must be called from @MainActor.
/// Uses @unchecked Sendable wrapper for mutable state accessed from C callbacks.
@MainActor
public struct WaylandApplication: LuminaApp, ~Copyable {
    public typealias Window = WaylandWindow
    /// Wrapper for mutable state accessed from C callbacks.
    ///
    /// SAFETY: @unchecked Sendable because all mutations happen on main thread via
    /// synchronous C callbacks during wl_display_dispatch()/roundtrip().
    internal final class State: @unchecked Sendable {
        var compositor: OpaquePointer?
        var shm: OpaquePointer?
        var seat: OpaquePointer?

        var libdecorReady: Bool = false
        var libdecorSyncCallback: OpaquePointer?

        /// Persistent listener structs (must not be stack-allocated)
        var registryListener: wl_registry_listener
        var syncCallbackListener: wl_callback_listener

        init() {
            self.registryListener = wl_registry_listener(
                global: registryGlobalCallback,
                global_remove: registryGlobalRemoveCallback
            )
            self.syncCallbackListener = wl_callback_listener(
                done: libdecorReadySyncCallback
            )
        }
    }

    /// Mutable state wrapper (fileprivate so nonisolated callbacks can access it)
    fileprivate let state = State()

    // MARK: - Core Wayland Resources

    private let display: OpaquePointer
    private var decorContext: OpaquePointer?
    private var decorInterface: UnsafeMutablePointer<libdecor_interface>?

    /// Shared interface for all windows
    private var frameInterface: UnsafeMutablePointer<libdecor_frame_interface>?

    private var registry: OpaquePointer?
    private var inputState: WaylandInputState?

    // MARK: - Event Loop State

    private var eventQueue: [Event] = []
    private let userEventQueue = UserEventQueue()
    private var windowRegistry = WindowRegistry<UnsafeRawPointer>()
    private var windows: [WindowID: Any] = [:]
    private var shouldQuit = false

    public var exitOnLastWindowClosed: Bool = true

    private let logger: LuminaLogger
    private var callbackContext: WaylandApplicationContext?

    // MARK: - Initialization

    /// Initialize Wayland application.
    ///
    /// Connects to the display and initializes input handling.
    /// Global interfaces and libdecor are initialized later on first use.
    ///
    /// - Throws: LuminaError.platformError if initialization fails
    public init() throws {
        self.logger = LuminaLogger(label: "com.lumina.wayland", level: .info)
        logger.logEvent("Initializing Wayland application")

        guard let display = wl_display_connect(nil) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "wl_display_connect",
                code: -1,
                message: "Failed to connect to Wayland display. Is WAYLAND_DISPLAY set?"
            )
        }
        self.display = display
        logger.logPlatformCall("wl_display_connect() -> \(display)")

        self.inputState = WaylandInputState()
        logger.logEvent("Input handling initialized")

        logger.logEvent("Wayland application initialized (waiting for completeInitialization)")
    }

    deinit {
        if let frameInterface = frameInterface {
            lumina_free_frame_interface(frameInterface)
        }

        if let decorInterface = decorInterface {
            lumina_free_libdecor_interface(decorInterface)
        }

        if let decorContext = decorContext {
            libdecor_unref(decorContext)
        }

        if let registry = registry {
            wl_registry_destroy(registry)
        }

        wl_display_disconnect(display)
    }

    /// Complete initialization by binding to global Wayland interfaces.
    ///
    /// Initialization steps:
    /// 1. Get registry and set up listener
    /// 2. Discover globals via two roundtrips
    /// 3. Create libdecor context
    /// 4. Create shared frame interface
    /// 5. Set up sync callback for libdecor readiness
    ///
    /// - Throws: LuminaError if initialization fails
    private mutating func completeInitialization() throws {
        guard let registry = wl_display_get_registry(display) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "wl_display_get_registry",
                code: -3,
                message: "Failed to get Wayland registry"
            )
        }
        self.registry = registry
        logger.logPlatformCall("wl_display_get_registry() -> \(registry)")

        let context = WaylandApplicationContext(state: self.state, inputState: self.inputState)
        self.callbackContext = context

        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        withUnsafeMutablePointer(to: &state.registryListener) { listenerPtr in
            wl_registry_add_listener(registry, listenerPtr, contextPtr)
        }
        logger.logPlatformCall("wl_registry_add_listener()")

        wl_display_roundtrip(display)
        logger.logPlatformCall("wl_display_roundtrip() #1 - discover globals")

        wl_display_roundtrip(display)
        logger.logPlatformCall("wl_display_roundtrip() #2 - initial events")

        guard state.compositor != nil else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_compositor")
        }
        guard state.shm != nil else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_shm")
        }
        logger.logEvent("Wayland global interfaces bound successfully")

        guard let decorInterface = lumina_alloc_libdecor_interface({ decorContext, error, message in
            if let msg = message {
                let errorStr = String(cString: msg)
                print("libdecor error (\(error.rawValue)): \(errorStr)")
            }
        }) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "lumina_alloc_libdecor_interface",
                code: -4,
                message: "Failed to allocate libdecor interface"
            )
        }
        self.decorInterface = decorInterface

        guard let decorContext = libdecor_new(display, decorInterface) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "libdecor_new",
                code: -5,
                message: "Failed to create libdecor context. Is libdecor-0 installed?"
            )
        }
        self.decorContext = decorContext
        logger.logPlatformCall("libdecor_new() -> \(decorContext)")

        _ = libdecor_dispatch(decorContext, 0)
        logger.logPlatformCall("libdecor_dispatch(0) - started initialization")

        guard let frameInterface = lumina_alloc_frame_interface(
            waylandFrameConfigureCallback,
            waylandFrameCloseCallback,
            waylandFrameCommitCallback
        ) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "lumina_alloc_frame_interface",
                code: -6,
                message: "Failed to allocate shared frame interface"
            )
        }
        self.frameInterface = frameInterface
        logger.logEvent("Created shared libdecor frame interface for all windows")

        if let syncCallback = wl_display_sync(display) {
            state.libdecorSyncCallback = syncCallback
            withUnsafeMutablePointer(to: &state.syncCallbackListener) { listenerPtr in
                wl_callback_add_listener(syncCallback, listenerPtr, contextPtr)
            }
            logger.logPlatformCall("wl_display_sync() - created libdecor ready callback")
        }

        logger.logEvent("Wayland initialization complete (libdecor ready callback registered)")
    }

    // MARK: - Event Loop (LuminaApp Protocol)

    public mutating func run() throws {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        logger.logEvent("Starting event loop")

        while !shouldQuit {
            if let event = pumpEvents(mode: .wait) {
                // Events are already queued and dispatched
                // Application code would handle events here
                processEvent(event)
            }
        }

        logger.logEvent("Event loop terminated")
    }

    public mutating func poll() throws -> Event? {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        return pumpEvents(mode: .poll)
    }

    public mutating func wait() throws {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        _ = pumpEvents(mode: .wait)
    }

    public mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
        // libdecor integration requires:
        // 1. Call libdecor_dispatch() to process any pending decoration events
        // 2. Read/dispatch Wayland events
        // 3. Call libdecor_dispatch() AGAIN to handle the events we just read
        //    This is CRITICAL - libdecor needs to process the events!

        // Process any pending libdecor events
        if let decorContext = decorContext {
            libdecor_dispatch(decorContext, 0)
        }

        // 2. Process Wayland protocol events based on mode
        switch mode {
        case .poll:
            // Non-blocking: dispatch only pending events
            while wl_display_dispatch_pending(display) > 0 { }
            // Process libdecor events that were triggered by the Wayland events
            if let decorContext = decorContext {
                libdecor_dispatch(decorContext, 0)
            }

        case .wait:
            // Blocking: wait for events using the proper prepare/read/dispatch pattern
            let fd = wl_display_get_fd(display)

            // Prepare to read - loop until prepare succeeds
            while wl_display_prepare_read(display) != 0 {
                // Dispatch any pending events that prevented prepare_read
                _ = wl_display_dispatch_pending(display)
            }

            // Flush outgoing requests
            _ = wl_display_flush(display)

            // Wait for events with poll()
            var pollfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = Glibc.poll(&pollfd, 1, -1)  // -1 = infinite timeout

            if pollResult > 0 {
                // Read events from the display
                _ = wl_display_read_events(display)
            } else {
                // Cancel the read if poll failed or timed out
                wl_display_cancel_read(display)
                if pollResult == -1 {
                    let errorMsg = String(cString: strerror(errno))
                    logger.logError("poll() failed: \(errorMsg)")
                }
            }

            // Dispatch the events we just read
            _ = wl_display_dispatch_pending(display)

            // CRITICAL: Process libdecor events triggered by the Wayland events
            if let decorContext = decorContext {
                libdecor_dispatch(decorContext, 0)
            }

        case .waitUntil(let deadline):
            // Blocking with timeout using the proper prepare/read/dispatch pattern
            let fd = wl_display_get_fd(display)
            let timeoutMs = deadline.hasExpired ? 0 : Int32(deadline.internalDate.timeIntervalSinceNow * 1000)

            if timeoutMs > 0 {
                // Prepare to read - loop until prepare succeeds
                while wl_display_prepare_read(display) != 0 {
                    // Dispatch any pending events that prevented prepare_read
                    _ = wl_display_dispatch_pending(display)
                }

                // Flush outgoing requests
                _ = wl_display_flush(display)

                // Wait for events with poll()
                var pollfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let pollResult = Glibc.poll(&pollfd, 1, timeoutMs)

                if pollResult > 0 {
                    // Read events from the display
                    _ = wl_display_read_events(display)
                } else {
                    // Cancel the read if poll failed or timed out
                    wl_display_cancel_read(display)
                    if pollResult == -1 {
                        let errorMsg = String(cString: strerror(errno))
                        logger.logError("poll() failed: \(errorMsg)")
                    }
                }

                // Dispatch the events we just read
                _ = wl_display_dispatch_pending(display)

                // CRITICAL: Process libdecor events triggered by the Wayland events
                if let decorContext = decorContext {
                    libdecor_dispatch(decorContext, 0)
                }
            } else {
                // Timeout already expired - just dispatch pending
                _ = wl_display_dispatch_pending(display)

                // CRITICAL: Process libdecor events triggered by the Wayland events
                if let decorContext = decorContext {
                    libdecor_dispatch(decorContext, 0)
                }
            }
        }

        // 3. Final flush of outgoing requests
        if wl_display_flush(display) == -1 && errno != EAGAIN {
            logger.logError("wl_display_flush failed")
            checkDisplayError()
        }

        // 4. Process input events from WaylandInputState
        if let inputState = inputState {
            while let inputEvent = inputState.dequeueEvent() {
                eventQueue.append(inputEvent)
            }
        }

        // 5. Process user events from background threads
        let userEvents = userEventQueue.removeAll()
        for userEvent in userEvents {
            eventQueue.append(.user(userEvent))
        }

        // 6. Return next queued event
        return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
    }

    /// Check for Wayland display protocol errors and handle recovery.
    private mutating func checkDisplayError() {
        let errorCode = wl_display_get_error(display)
        if errorCode != 0 {
            var interface: UnsafePointer<wl_interface>?
            var id: UInt32 = 0
            let protoError = wl_display_get_protocol_error(display, &interface, &id)

            let interfaceName = interface.map { String(cString: $0.pointee.name) } ?? "unknown"
            logger.logError("Wayland protocol error: code=\(protoError) interface=\(interfaceName) id=\(id)")

            // Critical error: compositor disconnected or protocol violation
            // In production, attempt graceful shutdown
            shouldQuit = true
        }
    }

    /// Dispatch libdecor events without blocking
    ///
    /// This should be called after operations that change window state (map, fullscreen, etc.)
    /// to allow libdecor to process the state change before entering the main event loop.
    internal mutating func dispatchDecorEvents() {
        // Non-blocking dispatch - process any pending decoration events
        // Note: libdecor_dispatch internally calls wl_display_dispatch_pending,
        // so we don't need to call it again here
        if let decorContext = decorContext {
            libdecor_dispatch(decorContext, 0)
        }

        // Flush outgoing requests
        _ = wl_display_flush(display)
    }

    /// Process a single event (placeholder for application logic).
    private mutating func processEvent(_ event: Event) {
        // This is where application event handlers would go
        // For now, just handle window close events
        switch event {
        case .window(.closed(let windowID)):
            // Remove window from registry
            windows.removeValue(forKey: windowID)

            // Check if we should quit
            if exitOnLastWindowClosed && windows.isEmpty {
                logger.logEvent("Last window closed, quitting application")
                quit()
            }
        default:
            break
        }
    }

    // MARK: - Window Management

    public mutating func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> WaylandWindow {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        // Ensure required globals are available
        logger.logEvent("Checking compositor: \(state.compositor != nil)")
        logger.logEvent("Checking shm: \(state.shm != nil)")

        guard let compositor = state.compositor else {
            throw LuminaError.windowCreationFailed(
                reason: "wl_compositor not available"
            )
        }

        guard let shm = state.shm else {
            throw LuminaError.windowCreationFailed(
                reason: "wl_shm not available"
            )
        }

        guard let decorContext = decorContext else {
            throw LuminaError.windowCreationFailed(
                reason: "libdecor context not ready"
            )
        }

        guard let frameInterface = frameInterface else {
            throw LuminaError.windowCreationFailed(
                reason: "libdecor frame interface not available"
            )
        }

        logger.logEvent("Compositor pointer: \(compositor)")
        logger.logEvent("Shm pointer: \(shm)")

        // Create the window using hybrid rendering: wl_egl_window + wl_shm default buffer
        print("[DEBUG] About to call WaylandWindow.create")
        let window = try WaylandWindow.create(
            decorContext: decorContext,
            frameInterface: frameInterface,
            display: display,
            compositor: compositor,
            shm: shm,
            title: title,
            size: size,
            resizable: resizable,
            application: callbackContext,
            inputState: inputState
        )
        print("[DEBUG] WaylandWindow.create returned")

        // With ~Copyable, window is moved to caller, not stored in application
        logger.logEvent("Created window \(window.id) '\(title)'")

        print("[DEBUG createWindow] About to return window")
        return window
    }

    // MARK: - Application Control

    public mutating func quit() {
        shouldQuit = true
        logger.logEvent("Application quit requested")
    }

    public nonisolated func postUserEvent(_ event: UserEvent) {
        userEventQueue.append(event)
    }

    // MARK: - Capabilities

    public static func monitorCapabilities() -> MonitorCapabilities {
        // Wayland monitor capabilities (conservative defaults)
        return MonitorCapabilities(
            supportsDynamicRefreshRate: false,  // Compositor-dependent
            supportsFractionalScaling: false    // Requires wp_fractional_scale_v1
        )
    }

    public static func clipboardCapabilities() -> ClipboardCapabilities {
        // Wayland clipboard capabilities
        return ClipboardCapabilities(
            supportsText: true,    // wl_data_device with text/plain
            supportsImages: false, // Future: image/png MIME type
            supportsHTML: false    // Future: text/html MIME type
        )
    }
}

// MARK: - Helper Types

/// Thread-safe user event queue for cross-thread event posting.
private final class UserEventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [UserEvent] = []

    func append(_ event: UserEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func removeAll() -> [UserEvent] {
        lock.lock()
        defer { lock.unlock() }
        let allEvents = events
        events.removeAll()
        return allEvents
    }
}

/// Context object to pass WaylandApplication state to C callbacks.
///
/// This is necessary because C callbacks receive void* userData, but we need
/// to access the Swift struct's state. We use Unmanaged to bridge the gap.
///
/// IMPORTANT: This stores only the State reference, not the entire WaylandApplication struct.
/// Storing the struct would create a copy, and callbacks would modify the wrong instance.
internal class WaylandApplicationContext {
    let state: WaylandApplication.State
    weak var inputState: WaylandInputState?
    let logger: LuminaLogger

    init(state: WaylandApplication.State, inputState: WaylandInputState? = nil) {
        self.state = state
        self.inputState = inputState
        self.logger = LuminaLogger(label: "com.lumina.wayland.context", level: .info)
    }

    /// Set compositor (accessor for private property).
    ///
    /// SAFETY: This is nonisolated because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip() or
    /// wl_display_dispatch(), which are themselves called from @MainActor pumpEvents().
    nonisolated func setCompositor(_ compositor: OpaquePointer) {
        state.compositor = compositor
        logger.logCapabilityDetection("wl_compositor bound")
    }

    /// Set shm (accessor for private property).
    ///
    /// SAFETY: This is nonisolated because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip() or
    /// wl_display_dispatch(), which are themselves called from @MainActor pumpEvents().
    nonisolated func setShm(_ shm: OpaquePointer) {
        state.shm = shm
        logger.logCapabilityDetection("wl_shm bound")
    }

    /// Set seat (accessor for private property).
    ///
    /// SAFETY: This is nonisolated because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip() or
    /// wl_display_dispatch(), which are themselves called from @MainActor pumpEvents().
    nonisolated func setSeat(_ seat: OpaquePointer) {
        state.seat = seat
        logger.logCapabilityDetection("wl_seat bound")
    }

    /// Handle global interface announcement from wl_registry.
    ///
    /// SAFETY: This is nonisolated because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip(),
    /// which is itself called from @MainActor completeInitialization().
    nonisolated func handleGlobal(registry: OpaquePointer?, name: UInt32, interface: UnsafePointer<CChar>, version: UInt32) {
        let interfaceName = String(cString: interface)

        logger.logPlatformCall("wl_registry.global: \(interfaceName) v\(version)")

        switch interfaceName {
        case "wl_compositor":
            // Bind to wl_compositor (version 4 or less)
            let boundVersion = min(version, 4)
            // Get interface pointer via C helper function (Swift can't take address of C globals)
            let interfacePtr = lumina_wl_compositor_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                let compositor = OpaquePointer(bound)
                setCompositor(compositor)
            }

        case "wl_shm":
            // Bind to wl_shm (version 1)
            let boundVersion = min(version, 1)
            // Get interface pointer via C helper function (Swift can't take address of C globals)
            let interfacePtr = lumina_wl_shm_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                let shm = OpaquePointer(bound)
                setShm(shm)
            }

        case "wl_seat":
            // Bind to wl_seat (version 5 or less)
            let boundVersion = min(version, 5)
            // Get interface pointer via C helper function (Swift can't take address of C globals)
            let interfacePtr = lumina_wl_seat_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                let seat = OpaquePointer(bound)
                setSeat(seat)

                // Pass seat to input state for input device setup
                // WaylandInputState will discover pointer/keyboard capabilities
                logger.logEvent("Delegating seat to input state")
                setupSeatListener(seat: seat)
            }

        default:
            // We do NOT bind xdg_wm_base manually - libdecor handles xdg-shell internally.
            // Other protocols (wl_output for monitors, etc.) will be handled later.
            break
        }
    }

    /// Set up wl_seat listener to detect input capabilities.
    ///
    /// SAFETY: This is nonisolated because it's only called from handleGlobal(),
    /// which itself runs synchronously on the main thread.
    nonisolated func setupSeatListener(seat: OpaquePointer) {
        // Delegate seat capabilities to input module
        if let inputState = self.inputState {
            inputState.setupSeatListener(seat)
            logger.logPlatformCall("Delegated wl_seat_add_listener to inputState")
        } else {
            logger.logError("Cannot set up seat listener - inputState not available")
        }
    }
}

// MARK: - C Function Pointers for Wayland Listeners

/// C callback for wl_registry global events
private func registryGlobalCallback(
    userData: UnsafeMutableRawPointer?,
    registry: OpaquePointer?,
    name: UInt32,
    interface: UnsafePointer<CChar>?,
    version: UInt32
) {
    guard let userData = userData, let interface = interface else { return }
    let context = Unmanaged<WaylandApplicationContext>.fromOpaque(userData).takeUnretainedValue()
    context.handleGlobal(registry: registry, name: name, interface: interface, version: version)
}

/// C callback for wl_registry global_remove events
private func registryGlobalRemoveCallback(
    userData: UnsafeMutableRawPointer?,
    registry: OpaquePointer?,
    name: UInt32
) {
    // Handle global removal (monitor disconnection, etc.)
    // For now, we don't need to handle this
}

/// C callback for libdecor ready sync
private func libdecorReadySyncCallback(
    userData: UnsafeMutableRawPointer?,
    callback: OpaquePointer?,
    time: UInt32
) {
    guard let userData = userData else { return }
    let context = Unmanaged<WaylandApplicationContext>.fromOpaque(userData).takeUnretainedValue()

    context.state.libdecorReady = true

    if let callback = callback {
        wl_callback_destroy(callback)
        context.state.libdecorSyncCallback = nil
    }
}

// MARK: - fd_set Utilities

/// Zero out an fd_set.
private func fdZero(_ set: inout fd_set) {
    #if os(Linux)
    set.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    #else
    #error("fd_set layout unknown for this platform")
    #endif
}

/// Add a file descriptor to an fd_set.
private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    #if os(Linux)
    let index = Int(fd) / (MemoryLayout<Int>.size * 8)
    let bit = Int(fd) % (MemoryLayout<Int>.size * 8)
    withUnsafeMutablePointer(to: &set.__fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int.self, capacity: 16) { intPtr in
            intPtr[index] |= (1 << bit)
        }
    }
    #else
    #error("fd_set layout unknown for this platform")
    #endif
}

// MARK: - XKB Constants

/// XKB context creation flags
private let XKB_CONTEXT_NO_FLAGS = xkb_context_flags(rawValue: 0)

// MARK: - Wayland Seat Capability Constants

private let WL_SEAT_CAPABILITY_POINTER: Int32 = 1
private let WL_SEAT_CAPABILITY_KEYBOARD: Int32 = 2
private let WL_SEAT_CAPABILITY_TOUCH: Int32 = 4

// MARK: - libdecor Frame Callbacks (C Function Pointers)

// These MUST be top-level functions (not closures, not methods) to convert to C function pointers

/// Handle configure event from libdecor (C callback)
///
/// Called by libdecor when the compositor configures the window (resize, maximize, etc.)
@_cdecl("waylandFrameConfigureCallback")
func waylandFrameConfigureCallback(
    _ frame: OpaquePointer?,
    _ configuration: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✓ handleConfigure CALLED!")
    print("  frame: \(String(describing: frame))")
    print("  configuration: \(String(describing: configuration))")
    print("  userData: \(String(describing: userData))")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    guard let frame = frame,
          let configuration = configuration,
          let userData = userData else {
        print("✗ handleConfigure: Missing required parameters!")
        return
    }

    let userDataPtr = userData.assumingMemoryBound(to: LuminaWindowUserData.self)

    // Get configured size from libdecor
    var width: Int32 = 0
    var height: Int32 = 0

    // Query content size from configuration
    if !libdecor_configuration_get_content_size(
        configuration,
        frame,
        &width,
        &height
    ) {
        // No size specified, use current size from user data
        width = Int32(userDataPtr.pointee.current_width)
        height = Int32(userDataPtr.pointee.current_height)
    }

    // Update current size in user data
    userDataPtr.pointee.current_width = Float(width)
    userDataPtr.pointee.current_height = Float(height)

    print("✓ handleConfigure: Configured size = \(width)x\(height)")

    // Mark window as configured (critical for show() wait loop)
    userDataPtr.pointee.configured = true
    print("✓ handleConfigure: Marked window as configured")

    // Resize EGL window BEFORE committing libdecor state to ensure buffers match
    if let eglWindow = userDataPtr.pointee.egl_window {
        wl_egl_window_resize(
            eglWindow,
            width,
            height,
            0,  // dx offset
            0   // dy offset
        )
        print("✓ handleConfigure: Resized EGL window to \(width)x\(height)")
    }

    // Update opaque region on resize
    if userDataPtr.pointee.surface != nil {
        // TODO: Update opaque region to match new size if compositor is available
    }

    // Create and attach a buffer so the window becomes visible!
    // Wayland requires at least one buffer attachment before windows appear.
    if let surface = userDataPtr.pointee.surface,
       let shm = userDataPtr.pointee.shm {

        let stride = width * 4  // 4 bytes per pixel (ARGB8888)
        let size = stride * height

        // Create anonymous file for shared memory using C helper
        let fd = lumina_memfd_create("lumina-buffer", 0)
        if fd >= 0 {
            ftruncate(fd, Int(size))

            // Map memory
            let data = mmap(nil, Int(size), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
            if data != MAP_FAILED {
                // Fill with light gray color (ARGB: 0xFFCCCCCC)
                let pixels = data!.assumingMemoryBound(to: UInt32.self)
                for i in 0..<Int(width * height) {
                    pixels[i] = 0xFFCCCCCC  // Light gray
                }
                munmap(data, Int(size))

                // Create wl_shm_pool
                let pool = wl_shm_create_pool(shm, fd, size)
                if let pool = pool {
                    // Create buffer from pool
                    let buffer = wl_shm_pool_create_buffer(
                        pool,
                        0,      // offset
                        width,
                        height,
                        stride,
                        WL_SHM_FORMAT_ARGB8888.rawValue
                    )

                    if let buffer = buffer {
                        // Attach buffer to surface
                        wl_surface_attach(surface, buffer, 0, 0)
                        wl_surface_damage(surface, 0, 0, width, height)
                        // Note: surface will be committed in waylandFrameCommitCallback

                        print("✓ handleConfigure: Created and attached \(width)x\(height) shm buffer")

                        // Clean up pool (buffer remains valid)
                        wl_shm_pool_destroy(pool)
                    }
                }
            }
            close(fd)
        }
    }

    // Create libdecor state with new size
    let state = libdecor_state_new(width, height)
    defer { libdecor_state_free(state) }

    // Commit the configuration (CRITICAL: Must always commit, even if size unchanged)
    libdecor_frame_commit(frame, state, configuration)

    print("✓ handleConfigure: Committed libdecor state")

    // The commit callback is only invoked when using client-side decorations.
    // With server-side decorations (SSD), we must manually commit the surface here.
    if let surface = userDataPtr.pointee.surface {
        wl_surface_commit(surface)
        print("✓ handleConfigure: Committed surface directly (SSD fallback)")
    }

    // TODO: Post window resized event to application event queue
}

/// Handle close request from libdecor (C callback)
///
/// Called by libdecor when the user clicks the window close button
@_cdecl("waylandFrameCloseCallback")
func waylandFrameCloseCallback(
    _ frame: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✓ CLOSE BUTTON CLICKED!")
    print("✓ Window close requested by user")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    print("✓ Triggering application exit...")

    // TEMPORARY: Exit immediately to demonstrate close button works
    // TODO: Post Event.window(.closeRequested(windowID)) to application event queue
    exit(0)
}

/// Handle commit request from libdecor (C callback)
///
/// Called by libdecor when the frame is ready to commit
@_cdecl("waylandFrameCommitCallback")
func waylandFrameCommitCallback(
    _ frame: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) {

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✓ COMMIT CALLBACK INVOKED!")
    print("  frame: \(String(describing: frame))")
    print("  userData: \(String(describing: userData))")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    // Commit the surface - essential for window visibility.
    // Without this, the compositor never receives surface state changes.

    guard let userData = userData else {
        print("⚠️ handleCommit: No user data")
        return
    }

    let windowData = userData.assumingMemoryBound(to: LuminaWindowUserData.self)
    let surface = windowData.pointee.surface

    guard let surface = surface else {
        print("⚠️ handleCommit: No surface in user data")
        return
    }

    wl_surface_commit(surface)

    print("✓ waylandFrameCommitCallback: Committed surface")
}

#endif // os(Linux) && LUMINA_WAYLAND
