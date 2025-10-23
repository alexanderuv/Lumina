#if os(Linux) && LUMINA_WAYLAND
import Foundation
import CWaylandClient

/// Wayland implementation of LuminaApp using libdecor for window decorations.
///
/// Architecture:
/// - Borrows wl_display connection from WaylandPlatform
/// - libdecor context for automatic SSD/CSD decoration handling
/// - wl_seat for input device management
/// - Event loop: libdecor_dispatch → wl_display_dispatch → wl_display_flush
///
/// Thread Safety: All methods must be called from @MainActor.
/// Uses @unchecked Sendable wrapper for mutable state accessed from C callbacks.
@MainActor
public final class WaylandApplication: LuminaApp {
    public typealias Window = WaylandWindow

    // MARK: - Platform Reference

    /// Strong reference to platform (keeps it alive)
    ///
    /// The platform owns the wl_display connection and must outlive the app.
    /// This strong reference ensures proper lifetime management.
    private unowned let platform: WaylandPlatform
    /// Wrapper for mutable state accessed from C callbacks.
    ///
    /// SAFETY: @unchecked Sendable because all mutations happen on main thread via
    /// synchronous C callbacks during wl_display_dispatch()/roundtrip().
    ///
    /// This is a pure data container with no logic.
    internal final class State: @unchecked Sendable {
        // Core protocols (required)
        var compositor: OpaquePointer?
        var shm: OpaquePointer?
        var seat: OpaquePointer?

        // Core protocols (optional but common)
        var subcompositor: OpaquePointer?
        var dataDeviceManager: OpaquePointer?
        var xdgWmBase: OpaquePointer?               // xdg_wm_base - shell protocol

        // Extension protocols (optional)
        var viewporter: OpaquePointer?              // wp_viewporter - viewport scaling
        var pointerConstraints: OpaquePointer?       // zwp_pointer_constraints_v1 - pointer locking
        var relativePointerManager: OpaquePointer?   // zwp_relative_pointer_manager_v1 - raw motion
        var decorationManager: OpaquePointer?        // zxdg_decoration_manager_v1 - server-side decoration

        // Cursor support
        var cursorTheme: OpaquePointer?              // wl_cursor_theme* - standard cursor size
        var cursorThemeHiDPI: OpaquePointer?         // wl_cursor_theme* - 2x size for HiDPI
        var cursorSurface: OpaquePointer?            // wl_surface* - cursor surface
        var currentCursorName: String?               // Currently set cursor name (for caching)
        var cursorHidden: Bool = false               // Track cursor visibility state

        var libdecorReady: Bool = false
        var libdecorSyncCallback: OpaquePointer?

        /// Persistent listener structs (must not be stack-allocated)
        var registryListener: wl_registry_listener?
        var syncCallbackListener: wl_callback_listener?
    }

    /// Mutable state wrapper (fileprivate so nonisolated callbacks can access it)
    fileprivate let state = State()

    // MARK: - Core Wayland Resources

    /// libdecor context (non-Sendable C type accessed from deinit)
    private nonisolated(unsafe) var decorContext: OpaquePointer?

    /// libdecor interface callbacks (non-Sendable C type accessed from deinit)
    private nonisolated(unsafe) var decorInterface: UnsafeMutablePointer<libdecor_interface>?

    /// Shared interface for all windows (non-Sendable C type accessed from deinit)
    private nonisolated(unsafe) var frameInterface: UnsafeMutablePointer<libdecor_frame_interface>?

    /// Wayland registry (non-Sendable C type accessed from deinit)
    private nonisolated(unsafe) var registry: OpaquePointer?

    /// Input state management (accessed from C callbacks)
    private nonisolated(unsafe) var inputState: WaylandInputState?

    /// Libdecor loader for dynamic loading
    private let libdecorLoader = LibdecorLoader.shared

    /// Cursor loader for dynamic loading
    internal let cursorLoader = WaylandCursorLoader.shared

    // MARK: - Event Loop State

    private var eventQueue: [Event] = []
    private let userEventQueue = UserEventQueue()
    private var windowRegistry = WindowRegistry<UnsafeRawPointer>()
    private var windows: [WindowID: Any] = [:]
    private var shouldQuit = false

    public var exitOnLastWindowClosed: Bool = true

    private let logger: LuminaLogger

    // MARK: - Initialization

    /// Initialize Wayland application from platform.
    ///
    /// The platform provides the wl_display connection and monitor tracker.
    /// Global interfaces and libdecor are initialized later on first use.
    ///
    /// **Internal:** Only WaylandPlatform can create applications.
    ///
    /// - Parameter platform: The WaylandPlatform that owns the display connection
    /// - Throws: LuminaError.platformError if initialization fails
    internal init(platform: WaylandPlatform) throws {
        self.platform = platform
        self.logger = LuminaLogger(label: "com.lumina.wayland", level: .info)
        self.inputState = WaylandInputState()
    }

    deinit {
        if let frameInterface = frameInterface {
            lumina_free_frame_interface(frameInterface)
        }

        if let decorInterface = decorInterface {
            lumina_free_libdecor_interface(decorInterface)
        }

        if let decorContext = decorContext,
           let libdecorUnref = libdecorLoader.libdecor_unref {
            libdecorUnref(decorContext)
        }

        // Clean up cursor resources
        if let cursorSurface = state.cursorSurface {
            wl_surface_destroy(cursorSurface)
        }

        if let cursorTheme = state.cursorTheme,
           let themeDestroy = cursorLoader.wl_cursor_theme_destroy {
            themeDestroy(cursorTheme)
        }

        if let cursorThemeHiDPI = state.cursorThemeHiDPI,
           let themeDestroy = cursorLoader.wl_cursor_theme_destroy {
            themeDestroy(cursorThemeHiDPI)
        }

        if let registry = registry {
            wl_registry_destroy(registry)
        }

        // Note: wl_display is owned by platform and will be cleaned up in platform.deinit
    }

    /// Complete initialization by binding to global Wayland interfaces.
    ///
    /// Initialization steps:
    /// 1. Get registry and set up listener
    /// 2. Discover globals via two roundtrips
    /// 3. Attempt to load libdecor (optional)
    ///
    /// - Throws: LuminaError if critical initialization fails
    private func completeInitialization() throws {
        let display = platform.displayConnection

        guard let registry = wl_display_get_registry(display) else {
            throw LuminaError.platformError(
                platform: "Wayland",
                operation: "wl_display_get_registry",
                code: -3,
                message: "Failed to get Wayland registry"
            )
        }
        self.registry = registry

        // Initialize registry listener and register callbacks
        state.registryListener = wl_registry_listener(
            global: registryGlobalCallback,
            global_remove: registryGlobalRemoveCallback
        )

        let appPtr = Unmanaged.passUnretained(self).toOpaque()
        _ = withUnsafeMutablePointer(to: &state.registryListener!) { listenerPtr in
            wl_registry_add_listener(registry, listenerPtr, appPtr)
        }

        wl_display_roundtrip(display)
        wl_display_roundtrip(display)

        guard state.compositor != nil else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_compositor")
        }
        guard state.shm != nil else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_shm")
        }

        // Attempt to load libdecor dynamically (optional)
        tryInitializeLibdecor(display: display, appPtr: appPtr)

        // Attempt to load cursor theme (optional)
        tryInitializeCursor()
    }

    /// Attempt to initialize libdecor if available
    /// Non-throwing - if it fails, we'll use SSD or CSD fallback
    private func tryInitializeLibdecor(display: OpaquePointer, appPtr: UnsafeMutableRawPointer) {
        guard libdecorLoader.load() else {
            print("[WaylandApplication] libdecor not available, will use fallback decorations")
            return
        }

        guard let decorInterface = lumina_alloc_libdecor_interface({ _, error, message in
            let errorStr = error == LIBDECOR_ERROR_COMPOSITOR_INCOMPATIBLE ? "compositor incompatible" : "invalid configuration"
            let msg = message.map { String(cString: $0) } ?? "unknown"
            print("[libdecor] Error: \(errorStr) - \(msg)")
        }) else {
            print("[WaylandApplication] Failed to allocate libdecor interface")
            return
        }
        self.decorInterface = decorInterface

        guard let libdecorNew = libdecorLoader.libdecor_new,
              let decorContext = libdecorNew(display, decorInterface) else {
            print("[WaylandApplication] Failed to create libdecor context")
            lumina_free_libdecor_interface(decorInterface)
            self.decorInterface = nil
            return
        }
        self.decorContext = decorContext

        guard let frameInterface = lumina_alloc_frame_interface(
            waylandFrameConfigureCallback,
            waylandFrameCloseCallback,
            waylandFrameCommitCallback
        ) else {
            print("[WaylandApplication] Failed to allocate frame interface")
            return
        }
        self.frameInterface = frameInterface

        // Dispatch and set up sync callback
        if let dispatch = libdecorLoader.libdecor_dispatch {
            _ = dispatch(decorContext, 0)
        }

        if let syncCallback = wl_display_sync(display) {
            state.libdecorSyncCallback = syncCallback
            state.syncCallbackListener = wl_callback_listener(done: libdecorReadySyncCallback)
            _ = withUnsafeMutablePointer(to: &state.syncCallbackListener!) { listenerPtr in
                wl_callback_add_listener(syncCallback, listenerPtr, appPtr)
            }
        }

        print("[WaylandApplication] libdecor initialized successfully")
    }

    /// Dispatch libdecor events using the dynamic loader
    private func dispatchLibdecor(timeout: Int32 = 0) {
        guard let decorContext = decorContext,
              let dispatch = libdecorLoader.libdecor_dispatch else {
            return
        }
        _ = dispatch(decorContext, timeout)
    }

    /// Attempt to initialize cursor theme if available
    /// Non-throwing - if it fails, cursor operations will be no-ops
    private func tryInitializeCursor() {
        guard cursorLoader.isAvailable else {
            logger.logInfo("libwayland-cursor not available, cursor support disabled")
            return
        }

        guard let compositor = state.compositor,
              let shm = state.shm else {
            logger.logError("Cannot initialize cursor: compositor or shm not available")
            return
        }

        // Read cursor size from environment
        var cursorSize: Int32 = 24  // Default size
        if let sizeString = ProcessInfo.processInfo.environment["XCURSOR_SIZE"],
           let size = Int32(sizeString) {
            cursorSize = size
        }

        // Read theme name from environment
        let themeName = ProcessInfo.processInfo.environment["XCURSOR_THEME"]

        // Load standard cursor theme
        if let themeLoad = cursorLoader.wl_cursor_theme_load {
            state.cursorTheme = themeName.withOptionalCString { namePtr in
                themeLoad(namePtr, cursorSize, shm)
            }

            if state.cursorTheme == nil {
                logger.logError("Failed to load cursor theme, cursor support disabled")
                return
            }

            // Load HiDPI theme (2x size, optional)
            state.cursorThemeHiDPI = themeName.withOptionalCString { namePtr in
                themeLoad(namePtr, cursorSize * 2, shm)
            }
        }

        // Create cursor surface
        state.cursorSurface = wl_compositor_create_surface(compositor)
        if state.cursorSurface == nil {
            logger.logError("Failed to create cursor surface")
            return
        }

        logger.logInfo("Cursor theme initialized successfully (size: \(cursorSize))")
    }

    // MARK: - Event Loop (LuminaApp Protocol)

    public func run() throws {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        while !shouldQuit {
            if let event = pumpEvents(mode: .wait) {
                // Events are already queued and dispatched
                // Application code would handle events here
                processEvent(event)
            }
        }
    }

    public func poll() throws -> Event? {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        return pumpEvents(mode: .poll)
    }

    public func wait() throws {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        _ = pumpEvents(mode: .wait)
    }

    public func pumpEvents(mode: ControlFlowMode) -> Event? {
        let display = platform.displayConnection

        // libdecor integration requires:
        // 1. Call libdecor_dispatch() to process any pending decoration events
        // 2. Read/dispatch Wayland events
        // 3. Call libdecor_dispatch() AGAIN to handle the events we just read
        //    This is CRITICAL - libdecor needs to process the events!

        // Process any pending libdecor events
        dispatchLibdecor()

        // 2. Process Wayland protocol events based on mode
        switch mode {
        case .poll:
            // Non-blocking: dispatch only pending events
            while wl_display_dispatch_pending(display) > 0 { }

            // CRITICAL: Flush outgoing requests to compositor
            // Without this, window resizes and other state changes won't be sent!
            _ = wl_display_flush(display)

            // Process libdecor events that were triggered by the Wayland events
            dispatchLibdecor()

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
            dispatchLibdecor()

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
                dispatchLibdecor()
            } else {
                // Timeout already expired - just dispatch pending
                _ = wl_display_dispatch_pending(display)

                // CRITICAL: Process libdecor events triggered by the Wayland events
                dispatchLibdecor()
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
    private func checkDisplayError() {
        let display = platform.displayConnection
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
    internal func dispatchDecorEvents() {
        // Non-blocking dispatch - process any pending decoration events
        // Note: libdecor_dispatch internally calls wl_display_dispatch_pending,
        // so we don't need to call it again here
        dispatchLibdecor()

        // Flush outgoing requests
        _ = wl_display_flush(platform.displayConnection)
    }

    /// Process a single event (placeholder for application logic).
    private func processEvent(_ event: Event) {
        // This is where application event handlers would go
        // For now, just handle window close events
        switch event {
        case .window(.closed(let windowID)):
            // Remove window from registry
            windows.removeValue(forKey: windowID)

            // Check if we should quit
            if exitOnLastWindowClosed && windows.isEmpty {
                quit()
            }
        default:
            break
        }
    }

    // MARK: - Window Management

    /// Select best available decoration strategy (3-tier fallback)
    /// 1. Try libdecor (best UX, compositor-aware)
    /// 2. Try server-side decorations (SSD)
    /// 3. Fall back to client-side decorations (CSD)
    /// 4. No decorations if nothing available
    private func selectDecorationStrategy() -> DecorationStrategy {
        // Tier 1: libdecor (dynamically loaded)
        if libdecorLoader.isAvailable, decorContext != nil {
            print("[WaylandApplication] Using libdecor decorations")
            return LibdecorDecorations(loader: libdecorLoader, display: platform.displayConnection)
        }

        // Tier 2: Server-side decorations
        if let decorationManager = state.decorationManager {
            print("[WaylandApplication] Using server-side decorations")
            return ServerSideDecorations(decorationManager: decorationManager)
        }

        // Tier 3: Client-side decorations
        if let compositor = state.compositor,
           let subcompositor = state.subcompositor,
           let shm = state.shm {
            print("[WaylandApplication] Using client-side decorations")
            return ClientSideDecorations(
                compositor: compositor,
                subcompositor: subcompositor,
                shm: shm,
                viewporter: state.viewporter
            )
        }

        // Tier 4: No decorations (borderless)
        print("[WaylandApplication] WARNING: No decoration method available, using borderless windows")
        return NoDecorations()
    }

    public func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> WaylandWindow {
        // Complete initialization if not already done
        if registry == nil {
            try completeInitialization()
        }

        let display = platform.displayConnection

        // Ensure required globals are available
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

        return try WaylandWindow(
            decorContext: decorContext,
            frameInterface: frameInterface,
            display: display,
            compositor: compositor,
            shm: shm,
            title: title,
            size: size,
            resizable: resizable,
            inputState: inputState,
            monitorTracker: platform.monitorTracker,
            application: self
        )
    }

    // MARK: - Application Control

    public func quit() {
        shouldQuit = true
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

    // MARK: - Callback Handlers (nonisolated for C callbacks)

    /// Handle global interface announcement from wl_registry.
    ///
    /// SAFETY: This is nonisolated because it's only called from Wayland callbacks
    /// that run synchronously on the main thread during wl_display_roundtrip(),
    /// which is itself called from @MainActor completeInitialization().
    nonisolated func handleGlobal(registry: OpaquePointer?, name: UInt32, interface: UnsafePointer<CChar>, version: UInt32) {
        let interfaceName = String(cString: interface)

        switch interfaceName {
        case "wl_compositor":
            // Bind to wl_compositor (version 4 or less)
            let boundVersion = min(version, 4)
            let interfacePtr = lumina_wl_compositor_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.compositor = OpaquePointer(bound)
            }

        case "wl_shm":
            // Bind to wl_shm (version 1)
            let boundVersion = min(version, 1)
            let interfacePtr = lumina_wl_shm_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.shm = OpaquePointer(bound)
            }

        case "wl_subcompositor":
            // Bind to wl_subcompositor (version 1) - for subsurfaces (client-side decorations)
            let boundVersion = min(version, 1)
            let interfacePtr = lumina_wl_subcompositor_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.subcompositor = OpaquePointer(bound)
            }

        case "wl_data_device_manager":
            // Bind to wl_data_device_manager (version 3 or less) - for clipboard/DnD
            let boundVersion = min(version, 3)
            let interfacePtr = lumina_wl_data_device_manager_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.dataDeviceManager = OpaquePointer(bound)
            }

        case "wl_seat":
            // Bind to wl_seat (version 5 or less)
            let boundVersion = min(version, 5)
            let interfacePtr = lumina_wl_seat_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                let seat = OpaquePointer(bound)
                state.seat = seat
                setupSeatListener(seat: seat)
            }

        case "wl_output":
            // wl_output is handled by WaylandPlatform, not the application
            break

        case "wp_viewporter":
            // Bind to wp_viewporter (version 1) - viewport scaling for HiDPI
            let boundVersion = min(version, 1)
            let interfacePtr = lumina_wp_viewporter_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.viewporter = OpaquePointer(bound)
            }

        case "zwp_pointer_constraints_v1":
            // Bind to zwp_pointer_constraints_v1 (version 1) - pointer locking/confinement
            let boundVersion = min(version, 1)
            let interfacePtr = lumina_zwp_pointer_constraints_v1_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.pointerConstraints = OpaquePointer(bound)
            }

        case "zwp_relative_pointer_manager_v1":
            // Bind to zwp_relative_pointer_manager_v1 (version 1) - raw mouse motion
            let boundVersion = min(version, 1)
            let interfacePtr = lumina_zwp_relative_pointer_manager_v1_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.relativePointerManager = OpaquePointer(bound)
            }

        case "zxdg_decoration_manager_v1":
            // Bind to zxdg_decoration_manager_v1 (version 1) - server-side decoration negotiation
            let boundVersion = min(version, 1)
            let interfacePtr = lumina_zxdg_decoration_manager_v1_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.decorationManager = OpaquePointer(bound)
            }

        case "xdg_wm_base":
            // Bind to xdg_wm_base (version 2 or less) - core shell protocol
            // Used when libdecor is not available
            let boundVersion = min(version, 2)
            let interfacePtr = lumina_xdg_wm_base_interface()
            if let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) {
                state.xdgWmBase = OpaquePointer(bound)
                // Set up ping listener for xdg_wm_base
                setupXdgWmBaseListener(OpaquePointer(bound))
            }

        default:
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
        }
    }

    /// Set up xdg_wm_base listener to handle ping events.
    ///
    /// SAFETY: This is nonisolated because it's only called from handleGlobal(),
    /// which itself runs synchronously on the main thread.
    nonisolated func setupXdgWmBaseListener(_ wmBase: OpaquePointer) {
        var listener = xdg_wm_base_listener(
            ping: { userData, wmBase, serial in
                guard let wmBase = wmBase else { return }
                xdg_wm_base_pong(wmBase, serial)
            }
        )

        _ = withUnsafePointer(to: &listener) { listenerPtr in
            xdg_wm_base_add_listener(wmBase, listenerPtr, nil)
        }
    }

    // MARK: - Internal Cursor Access (for WaylandCursor)

    /// Access cursor state for WaylandCursor operations (internal to Wayland platform)
    internal var cursorState: (
        currentName: String?,
        hidden: Bool,
        surface: OpaquePointer?,
        theme: OpaquePointer?,
        themeHiDPI: OpaquePointer?
    ) {
        get {
            (state.currentCursorName, state.cursorHidden, state.cursorSurface, state.cursorTheme, state.cursorThemeHiDPI)
        }
        set {
            state.currentCursorName = newValue.currentName
            state.cursorHidden = newValue.hidden
        }
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

// MARK: - C Function Pointers for Wayland Listeners

/// C callback for wl_registry global events
private func registryGlobalCallback(
    userData: UnsafeMutableRawPointer?,
    registry: OpaquePointer?,
    name: UInt32,
    interface: UnsafePointer<CChar>?,
    version: UInt32
) {
    guard let userData, let interface else { return }
    let app = Unmanaged<WaylandApplication>.fromOpaque(userData).takeUnretainedValue()
    app.handleGlobal(registry: registry, name: name, interface: interface, version: version)
}

/// C callback for wl_registry global_remove events
private func registryGlobalRemoveCallback(
    userData: UnsafeMutableRawPointer?,
    registry: OpaquePointer?,
    name: UInt32
) {
    // Monitor removal is handled by WaylandPlatform
    // Other global removals can be handled here in the future
}

/// C callback for libdecor ready sync
private func libdecorReadySyncCallback(
    userData: UnsafeMutableRawPointer?,
    callback: OpaquePointer?,
    time: UInt32
) {
    guard let userData else { return }
    let app = Unmanaged<WaylandApplication>.fromOpaque(userData).takeUnretainedValue()

    app.state.libdecorReady = true

    if let callback = callback {
        wl_callback_destroy(callback)
        app.state.libdecorSyncCallback = nil
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
    guard let frame, let configuration, let userData else {
        return
    }

    let userDataPtr = userData.assumingMemoryBound(to: LuminaWindowUserData.self)
    let loader = LibdecorLoader.shared

    // Get configured size from libdecor
    var width: Int32 = 0
    var height: Int32 = 0

    // Query content size from configuration using dynamic loader
    if let getContentSize = loader.libdecor_configuration_get_content_size {
        if !getContentSize(configuration, frame, &width, &height) {
            // No size specified, use current size from user data
            width = Int32(userDataPtr.pointee.current_width)
            height = Int32(userDataPtr.pointee.current_height)
        }
    } else {
        // Loader not available, use current size
        width = Int32(userDataPtr.pointee.current_width)
        height = Int32(userDataPtr.pointee.current_height)
    }

    // CRITICAL: Commit libdecor state FIRST
    // This must happen BEFORE any surface operations
    if let stateNew = loader.libdecor_state_new,
       let stateFree = loader.libdecor_state_free,
       let frameCommit = loader.libdecor_frame_commit,
       let state = stateNew(width, height) {
        defer { stateFree(state) }
        frameCommit(frame, state, configuration)
    }

    // Check if this is first configure or if size changed
    let isFirstConfigure = !userDataPtr.pointee.configured
    let oldWidth = Int32(userDataPtr.pointee.current_width)
    let oldHeight = Int32(userDataPtr.pointee.current_height)
    let sizeChanged = (width != oldWidth || height != oldHeight)

    // Only proceed with resize if size actually changed or first configure
    guard isFirstConfigure || sizeChanged else {
        // No size change, just mark as configured and return
        userDataPtr.pointee.configured = true
        return
    }

    // Update current size in user data
    userDataPtr.pointee.current_width = Float(width)
    userDataPtr.pointee.current_height = Float(height)

    // Resize EGL window
    if let eglWindow = userDataPtr.pointee.egl_window {
        wl_egl_window_resize(eglWindow, width, height, 0, 0)
    }

    // Update opaque region
    if let surface = userDataPtr.pointee.surface,
       let compositor = userDataPtr.pointee.compositor {
        let region = wl_compositor_create_region(compositor)
        if let region = region {
            wl_region_add(region, 0, 0, width, height)
            wl_surface_set_opaque_region(surface, region)
            wl_region_destroy(region)
        }
    }

    // For demo purposes, create a new buffer to show resize working
    // Production apps would use OpenGL/Vulkan which provides buffers automatically
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
                        wl_surface_attach(surface, buffer, 0, 0)
                        wl_surface_damage(surface, 0, 0, width, height)
                        wl_shm_pool_destroy(pool)
                    }
                }
            }
            close(fd)
        }
    }

    // Commit surface after buffer attach
    if let surface = userDataPtr.pointee.surface {
        wl_surface_commit(surface)
    }

    // Mark as configured
    userDataPtr.pointee.configured = true
}

/// Handle close request from libdecor (C callback)
///
/// Called by libdecor when the user clicks the window close button
@_cdecl("waylandFrameCloseCallback")
func waylandFrameCloseCallback(
    _ frame: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) {
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
    guard let userData = userData else { return }

    let windowData = userData.assumingMemoryBound(to: LuminaWindowUserData.self)
    guard let surface = windowData.pointee.surface else { return }

    wl_surface_commit(surface)
}

// MARK: - Helper Extensions

/// Helper extension for Optional<String> to work with C string pointers
private extension Optional where Wrapped == String {
    func withOptionalCString<Result>(_ body: (UnsafePointer<CChar>?) -> Result) -> Result {
        switch self {
        case .some(let string):
            return string.withCString(body)
        case .none:
            return body(nil)
        }
    }
}

#endif // os(Linux) && LUMINA_WAYLAND
