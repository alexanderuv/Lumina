#if os(Linux) && LUMINA_WAYLAND
import Foundation
import CWaylandClient

/// Wayland implementation of LuminaApp using libdecor.
///
/// This implementation follows SDL3/GLFW best practices:
/// - Uses libdecor as the PRIMARY decoration method
/// - Event loop: libdecor_dispatch → wl_display_dispatch → wl_display_flush
/// - Proper resource cleanup in reverse order of creation
/// - Comprehensive error handling with recovery paths
///
/// Architecture:
/// - Display connection via wl_display_connect()
/// - libdecor context for decoration management (automatic SSD/CSD selection)
/// - wl_seat discovery for input capability management
/// - Event loop with poll/wait/waitUntil control flow modes
///
/// Thread Safety: All methods must be called from @MainActor.
///
/// SAFETY: Uses @unchecked Sendable wrapper pattern for mutable state accessed from C callbacks.
@MainActor
public struct WaylandApplication: LuminaApp {
    /// Wrapper for mutable state accessed from C callbacks.
    ///
    /// SAFETY: @unchecked Sendable because all mutations happen on main thread via
    /// synchronous C callbacks during wl_display_dispatch()/roundtrip().
    fileprivate final class State: @unchecked Sendable {
        var compositor: OpaquePointer?
        var shm: OpaquePointer?
        var seat: OpaquePointer?
        var pointer: OpaquePointer?
        var keyboard: OpaquePointer?
    }

    /// Mutable state wrapper (fileprivate so nonisolated callbacks can access it)
    fileprivate let state = State()

    // MARK: - Core Wayland Resources

    /// Wayland display connection
    private let display: OpaquePointer

    /// libdecor context (PRIMARY decoration path)
    private let decorContext: OpaquePointer

    /// Wayland registry for global interface discovery
    private var registry: OpaquePointer?

    /// XKB context for keyboard handling
    private var xkbContext: OpaquePointer?

    /// XKB state for modifier tracking
    private var xkbState: OpaquePointer?

    /// XKB keymap (current keyboard layout)
    private var xkbKeymap: OpaquePointer?

    // MARK: - Event Loop State

    /// Event queue for application events
    private var eventQueue: [Event] = []

    /// User event queue (thread-safe access required)
    private let userEventQueue = UserEventQueue()

    /// Window registry (wl_surface* -> WindowID mapping)
    private var windowRegistry = WindowRegistry<UnsafeRawPointer>()

    /// Active windows (WindowID -> WaylandWindow mapping)
    private var windows: [WindowID: Any] = [:]  // Will store WaylandWindow instances

    /// Whether the application should quit
    private var shouldQuit = false

    /// Whether to quit when last window closes
    public var exitOnLastWindowClosed: Bool = true

    /// Logger for Wayland platform operations
    private let logger: LuminaLogger

    /// Context for C callback handling (must be kept alive)
    private var callbackContext: WaylandApplicationContext?

    // MARK: - Initialization

    /// Initialize Wayland application.
    ///
    /// This performs the complete Wayland initialization sequence:
    /// 1. Connect to Wayland display server
    /// 2. Create libdecor context
    /// 3. Bind to required global interfaces (compositor, shm)
    /// 4. Discover and configure input seat
    /// 5. Initialize XKB for keyboard handling
    ///
    /// - Throws: LuminaError.platformError if initialization fails
    public init() throws {
        // Initialize logger first
        self.logger = LuminaLogger(label: "com.lumina.wayland", level: .info)
        logger.logEvent("Initializing Wayland application")

        // 1. Connect to Wayland display
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

        // 2. Create libdecor context (PRIMARY decoration method)
        // Provide error callback interface - libdecor requires this
        guard let decorInterface = lumina_alloc_libdecor_interface({ decorContext, error, message in
            if let msg = message {
                let errorStr = String(cString: msg)
                print("libdecor error (\(error.rawValue)): \(errorStr)")
            }
        }) else {
            wl_display_disconnect(display)
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "lumina_alloc_libdecor_interface",
                code: -2,
                message: "Failed to allocate libdecor interface"
            )
        }

        guard let decorContext = libdecor_new(display, decorInterface) else {
            lumina_free_libdecor_interface(decorInterface)
            wl_display_disconnect(display)
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "libdecor_new",
                code: -2,
                message: "Failed to create libdecor context. Is libdecor-0 installed?"
            )
        }
        self.decorContext = decorContext
        logger.logPlatformCall("libdecor_new() -> \(decorContext)")

        // 3. Initialize XKB context for keyboard handling
        if let xkbCtx = xkb_context_new(XKB_CONTEXT_NO_FLAGS) {
            self.xkbContext = xkbCtx
            logger.logPlatformCall("xkb_context_new() -> \(xkbCtx)")
        } else {
            logger.logError("Failed to create XKB context, keyboard input will be limited")
        }

        // 4. Set up registry to bind global interfaces
        // NOTE: bindGlobalInterfaces() is called mutating, so we need to defer it
        // We'll do this in a second pass after struct initialization

        logger.logEvent("Wayland application initialized successfully")
    }

    /// Complete initialization by binding to global Wayland interfaces.
    ///
    /// This must be called after init() as a mutating method.
    /// It discovers and binds to essential Wayland protocols:
    /// - wl_compositor (required for surface creation)
    /// - wl_shm (required for buffer allocation)
    /// - wl_seat (required for input events)
    ///
    /// - Throws: LuminaError if registry enumeration fails
    private mutating func completeInitialization() throws {
        // Get registry for global interface discovery
        guard let registry = wl_display_get_registry(display) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "wl_display_get_registry",
                code: -3,
                message: "Failed to get Wayland registry"
            )
        }
        self.registry = registry

        // Create callback context (must be kept alive)
        // Pass only the State reference to avoid copying the noncopyable struct
        let context = WaylandApplicationContext(state: self.state)
        self.callbackContext = context

        // Set up registry listener with C function pointers
        // CRITICAL: Must use static C function pointers, NOT Swift closures
        // Swift closures are heap-allocated and will be deallocated after this scope,
        // causing dangling pointers when Wayland tries to invoke callbacks
        var registryListener = wl_registry_listener(
            global: registryGlobalCallback,
            global_remove: registryGlobalRemoveCallback
        )

        let contextPtr = Unmanaged.passUnretained(context).toOpaque()
        wl_registry_add_listener(registry, &registryListener, contextPtr)
        logger.logPlatformCall("wl_registry_add_listener()")

        // Perform roundtrip to ensure all globals are discovered
        wl_display_roundtrip(display)
        logger.logPlatformCall("wl_display_roundtrip()")

        // Verify required interfaces were found
        guard state.compositor != nil else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_compositor")
        }
        guard state.shm != nil else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_shm")
        }

        logger.logEvent("Wayland global interfaces bound successfully")
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
        // SDL3 pattern: libdecor first, then Wayland, then flush

        // 1. Process libdecor events (decoration configure, close, etc.)
        libdecor_dispatch(decorContext, 0)  // Non-blocking

        // 2. Process Wayland protocol events
        switch mode {
        case .poll:
            // Non-blocking: dispatch only pending events
            while wl_display_dispatch_pending(display) > 0 { }

        case .wait:
            // Blocking: wait for events with infinite timeout
            if wl_display_dispatch(display) == -1 {
                logger.logError("wl_display_dispatch failed, checking for protocol error")
                checkDisplayError()
            }

        case .waitUntil(let deadline):
            // Blocking with timeout
            let fd = wl_display_get_fd(display)
            let timeoutMs = deadline.hasExpired ? 0 : Int32(deadline.internalDate.timeIntervalSinceNow * 1000)

            if timeoutMs > 0 {
                // Use select() to wait with timeout
                var readfds = fd_set()
                fdZero(&readfds)
                fdSet(fd, &readfds)

                var timeout = timeval(
                    tv_sec: Int(timeoutMs / 1000),
                    tv_usec: Int((timeoutMs % 1000) * 1000)
                )

                let result = select(fd + 1, &readfds, nil, nil, &timeout)
                if result > 0 {
                    // Events available
                    _ = wl_display_dispatch(display)
                } else if result == -1 {
                    let errorMsg = String(cString: strerror(errno))
                    logger.logError("select() failed: \(errorMsg)")
                }
            }

            // Dispatch any pending events
            while wl_display_dispatch_pending(display) > 0 { }
        }

        // 3. Flush outgoing requests
        if wl_display_flush(display) == -1 {
            logger.logError("wl_display_flush failed")
            checkDisplayError()
        }

        // 4. Process user events from background threads
        let userEvents = userEventQueue.removeAll()
        for userEvent in userEvents {
            eventQueue.append(.user(userEvent))
        }

        // 5. Return next queued event
        return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
    }

    /// Check for Wayland display protocol errors and handle recovery.
    private func checkDisplayError() {
        let errorCode = wl_display_get_error(display)
        if errorCode != 0 {
            var interface: UnsafePointer<wl_interface>?
            var id: UInt32 = 0
            let protoError = wl_display_get_protocol_error(display, &interface, &id)

            let interfaceName = interface.map { String(cString: $0.pointee.name) } ?? "unknown"
            logger.logError("Wayland protocol error: code=\(protoError) interface=\(interfaceName) id=\(id)")

            // Critical error: compositor disconnected or protocol violation
            // In production, attempt graceful shutdown
            var mutableSelf = self
            mutableSelf.shouldQuit = true
        }
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
    ) throws -> LuminaWindow {
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

        logger.logEvent("Compositor pointer: \(compositor)")
        logger.logEvent("Shm pointer: \(shm)")

        // Create the window using WaylandWindow
        let window = try WaylandWindow.create(
            decorContext: decorContext,
            compositor: compositor,
            shm: shm,
            title: title,
            size: size,
            resizable: resizable,
            application: callbackContext
        )

        // Register window
        windows[window.id] = window
        logger.logEvent("Created window \(window.id) '\(title)'")

        return window
    }

    // MARK: - Application Control

    public func quit() {
        var mutableSelf = self
        mutableSelf.shouldQuit = true
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
private class WaylandApplicationContext {
    let state: WaylandApplication.State
    let logger: LuminaLogger

    init(state: WaylandApplication.State) {
        self.state = state
        self.logger = LuminaLogger(label: "com.lumina.wayland.context", level: .info)
    }

    /// Set compositor (accessor for private property).
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip() or
    /// wl_display_dispatch(), which are themselves called from @MainActor pumpEvents().
    nonisolated(unsafe) func setCompositor(_ compositor: OpaquePointer) {
        state.compositor = compositor
        logger.logCapabilityDetection("wl_compositor bound")
    }

    /// Set shm (accessor for private property).
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip() or
    /// wl_display_dispatch(), which are themselves called from @MainActor pumpEvents().
    nonisolated(unsafe) func setShm(_ shm: OpaquePointer) {
        state.shm = shm
        logger.logCapabilityDetection("wl_shm bound")
    }

    /// Set seat (accessor for private property).
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip() or
    /// wl_display_dispatch(), which are themselves called from @MainActor pumpEvents().
    nonisolated(unsafe) func setSeat(_ seat: OpaquePointer) {
        state.seat = seat
        logger.logCapabilityDetection("wl_seat bound")
    }

    /// Set pointer (accessor for private property).
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_dispatch(),
    /// which is itself called from @MainActor pumpEvents().
    nonisolated(unsafe) func setPointer(_ pointer: OpaquePointer) {
        state.pointer = pointer
        logger.logPlatformCall("wl_seat_get_pointer()")
    }

    /// Set keyboard (accessor for private property).
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_dispatch(),
    /// which is itself called from @MainActor pumpEvents().
    nonisolated(unsafe) func setKeyboard(_ keyboard: OpaquePointer) {
        state.keyboard = keyboard
        logger.logPlatformCall("wl_seat_get_keyboard()")
    }

    /// Handle global interface announcement from wl_registry.
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip(),
    /// which is itself called from @MainActor completeInitialization().
    nonisolated(unsafe) func handleGlobal(registry: OpaquePointer?, name: UInt32, interface: UnsafePointer<CChar>, version: UInt32) {
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

                // Set up seat capabilities listener
                setupSeatListener(seat: seat)
            }

        default:
            // Other protocols (wl_output for monitors, etc.) will be handled later
            break
        }
    }

    /// Set up wl_seat listener to detect input capabilities.
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from handleGlobal(),
    /// which itself runs synchronously on the main thread.
    nonisolated(unsafe) func setupSeatListener(seat: OpaquePointer) {
        // Use C function pointers instead of Swift closures
        var listener = wl_seat_listener(
            capabilities: seatCapabilitiesCallback,
            name: seatNameCallback
        )

        let contextPtr = Unmanaged.passUnretained(self).toOpaque()
        wl_seat_add_listener(seat, &listener, contextPtr)
        logger.logPlatformCall("wl_seat_add_listener()")
    }

    /// Handle wl_seat capabilities announcement.
    ///
    /// SAFETY: This is nonisolated(unsafe) because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_dispatch(),
    /// which is itself called from @MainActor pumpEvents().
    nonisolated(unsafe) func handleSeatCapabilities(seat: OpaquePointer?, capabilities: UInt32) {
        let hasPointer = (capabilities & UInt32(WL_SEAT_CAPABILITY_POINTER)) != 0
        let hasKeyboard = (capabilities & UInt32(WL_SEAT_CAPABILITY_KEYBOARD)) != 0

        logger.logCapabilityDetection("wl_seat capabilities: pointer=\(hasPointer) keyboard=\(hasKeyboard)")

        // Get pointer device
        if hasPointer {
            if let pointer = wl_seat_get_pointer(seat) {
                setPointer(pointer)
                // TODO: Set up pointer listener (will be implemented in WaylandInput.swift)
            }
        }

        // Get keyboard device
        if hasKeyboard {
            if let keyboard = wl_seat_get_keyboard(seat) {
                setKeyboard(keyboard)
                // TODO: Set up keyboard listener (will be implemented in WaylandInput.swift)
            }
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

/// C callback for wl_seat capabilities events
private func seatCapabilitiesCallback(
    userData: UnsafeMutableRawPointer?,
    seat: OpaquePointer?,
    capabilities: UInt32
) {
    guard let userData = userData else { return }
    let context = Unmanaged<WaylandApplicationContext>.fromOpaque(userData).takeUnretainedValue()
    context.handleSeatCapabilities(seat: seat, capabilities: capabilities)
}

/// C callback for wl_seat name events
private func seatNameCallback(
    userData: UnsafeMutableRawPointer?,
    seat: OpaquePointer?,
    name: UnsafePointer<CChar>?
) {
    // Seat name callback (optional)
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

#endif // os(Linux) && LUMINA_WAYLAND
