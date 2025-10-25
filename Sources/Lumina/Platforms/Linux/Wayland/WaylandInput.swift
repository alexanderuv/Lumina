#if os(Linux) && LUMINA_WAYLAND
import CWaylandClient
import Foundation

/// Wayland input event translation layer.
///
/// This module manages wl_seat, wl_pointer, and wl_keyboard input device interfaces,
/// translating Wayland input events to Lumina's cross-platform Event types. It handles:
/// - Seat capability detection and device initialization
/// - Mouse pointer enter/leave/motion/button/axis/frame events
/// - Keyboard keymap/enter/leave/key/modifiers events with XKB integration
/// - Surface-to-WindowID mapping for event routing
/// - Text input generation from XKB state
///
/// Architecture:
/// - XKB context for keyboard layout interpretation
/// - Frame-based pointer event coalescing
/// - Modifier key state tracking
/// - Safe C callback bridging via Unmanaged
///
/// Example usage:
/// ```swift
/// // During WaylandApplication initialization:
/// let inputState = WaylandInputState()
///
/// // Register seat listener when wl_seat global appears:
/// wl_seat_add_listener(seat, &seatListener, Unmanaged.passUnretained(inputState).toOpaque())
///
/// // In event loop:
/// while let event = inputState.dequeueEvent() {
///     handleEvent(event)
/// }
/// ```
///
/// SAFETY: This class uses @unchecked Sendable with a wrapper pattern for mutable state.
/// All mutable state is contained in `State` which is @unchecked Sendable because we
/// guarantee that C callbacks only run synchronously on the main thread during
/// wl_display_dispatch(), which is called from @MainActor methods.
/// Decoration area for client-side decorations
enum DecorationArea: Sendable {
    case titleBar
    case leftBorder
    case rightBorder
    case bottomBorder
    case topLeftCorner
    case topRightCorner
    case bottomLeftCorner
    case bottomRightCorner
}

@MainActor
final class WaylandInputState {
    /// Weak reference to application (for cursor restoration on pointer enter)
    nonisolated(unsafe) fileprivate weak var application: WaylandApplication?

    /// Wrapper for mutable state accessed from C callbacks.
    ///
    /// SAFETY: @unchecked Sendable because all mutations happen on main thread via
    /// synchronous C callbacks during wl_display_dispatch().
    internal final class State: @unchecked Sendable {
        // Input Devices
        var seat: OpaquePointer?
        var pointer: OpaquePointer?
        var keyboard: OpaquePointer?

        // XKB State
        var xkbKeymap: OpaquePointer?
        var xkbState: OpaquePointer?

        // Event State
        var eventQueue: [Event] = []
        var surfaceToWindowID: [UInt: WindowID] = [:]
        var focusedWindowID: WindowID?
        var pointerSurface: OpaquePointer?
        var pointerWindowID: WindowID?
        var pointerX: Float = 0.0
        var pointerY: Float = 0.0
        var pointerEnterSerial: UInt32 = 0  // Serial from last pointer enter event (for cursor)
        var hasPendingMotion = false

        // Main content surface tracking (like GLFW's approach)
        // Maps WindowID -> main content surface pointer
        var windowMainSurfaces: [WindowID: OpaquePointer] = [:]
        // True if pointer is currently over the main content surface (not decorations)
        var pointerOnMainSurface = false

        // Client-side decoration tracking
        var decorationSurfaces: [UInt: (windowID: WindowID, area: DecorationArea)] = [:]
        var pointerOnDecoration: DecorationArea?

        // Modifier key state (tracked from keyboard events)
        var modifiers: ModifierKeys = []

        /// Persistent listener structs (must remain alive for Wayland object lifetime)
        /// CRITICAL: These CANNOT be stack-allocated or they become dangling pointers.
        /// use static const structs; Swift stores them as instance variables.
        var seatListener: wl_seat_listener
        var pointerListener: wl_pointer_listener
        var keyboardListener: wl_keyboard_listener

        init() {
            // Initialize listener structs with C callback function pointers
            self.seatListener = wl_seat_listener(
                capabilities: seatCapabilitiesCallback,
                name: seatNameCallback
            )
            self.pointerListener = wl_pointer_listener(
                enter: pointerEnterCallback,
                leave: pointerLeaveCallback,
                motion: pointerMotionCallback,
                button: pointerButtonCallback,
                axis: pointerAxisCallback,
                frame: pointerFrameCallback,
                axis_source: pointerAxisSourceCallback,
                axis_stop: pointerAxisStopCallback,
                axis_discrete: pointerAxisDiscreteCallback,
                axis_value120: nil,
                axis_relative_direction: nil
            )
            self.keyboardListener = wl_keyboard_listener(
                keymap: keyboardKeymapCallback,
                enter: keyboardEnterCallback,
                leave: keyboardLeaveCallback,
                key: keyboardKeyCallback,
                modifiers: keyboardModifiersCallback,
                repeat_info: keyboardRepeatInfoCallback
            )
        }
    }

    /// Mutable state wrapper (fileprivate so nonisolated callbacks can access it)
    internal let state = State()

    /// XKB context for keyboard layout interpretation (immutable after init, nonisolated(unsafe) for callback access)
    ///
    /// SAFETY: nonisolated(unsafe) is safe here because xkbContext is immutable after initialization
    /// and OpaquePointer itself is thread-safe (just a pointer).
    nonisolated(unsafe) fileprivate let xkbContext: OpaquePointer?

    // MARK: - Initialization

    init() {
        // Create XKB context for keyboard handling
        self.xkbContext = xkb_context_new(XKB_CONTEXT_NO_FLAGS)

        if self.xkbContext == nil {
            // Non-fatal: keyboard input will be degraded but application can still run
            logger.error("Failed to create XKB context - keyboard input will be limited")
        }
    }

    deinit {
        MainActor.assumeIsolated {
            // Release input devices
            if let pointer = state.pointer {
                wl_pointer_release(pointer)
            }

            if let keyboard = state.keyboard {
                wl_keyboard_release(keyboard)
            }

            // Release XKB resources
            if let xkbState = state.xkbState {
                xkb_state_unref(xkbState)
            }

            if let xkbKeymap = state.xkbKeymap {
                xkb_keymap_unref(xkbKeymap)
            }

            if let xkbContext = xkbContext {
                xkb_context_unref(xkbContext)
            }
        }
    }

    // MARK: - Surface Mapping

    /// Register a surface-to-WindowID mapping for event routing.
    ///
    /// This must be called when creating windows to enable proper event routing.
    /// Wayland events reference wl_surface pointers, which we map to WindowIDs.
    ///
    /// NOTE: libdecor_decorate will overwrite surface user data with LuminaWindowUserData,
    /// so we only maintain the dictionary mapping for cleanup.
    ///
    /// - Parameters:
    ///   - surface: The wl_surface pointer
    ///   - windowID: The Lumina WindowID to associate with this surface
    ///   - isMainSurface: True if this is the main content surface (not a decoration surface)
    func registerSurface(_ surface: OpaquePointer, windowID: WindowID, isMainSurface: Bool = true) {
        let surfaceID = UInt(bitPattern: surface)
        state.surfaceToWindowID[surfaceID] = windowID

        // Track main content surface for proper input event filtering (like GLFW)
        if isMainSurface {
            state.windowMainSurfaces[windowID] = surface
        }
    }

    /// Unregister a surface mapping when a window is closed.
    ///
    /// - Parameter surface: The wl_surface pointer to unregister
    func unregisterSurface(_ surface: OpaquePointer) {
        let surfaceID = UInt(bitPattern: surface)
        state.surfaceToWindowID.removeValue(forKey: surfaceID)

        // Clear focus/pointer if this was the active surface
        if state.pointerSurface == surface {
            state.pointerSurface = nil
            state.pointerWindowID = nil
        }
    }

    /// Register a decoration surface for client-side decorations.
    ///
    /// SAFETY: nonisolated because it only modifies the state dictionary which is safe
    /// since all modifications happen on the main thread.
    ///
    /// - Parameters:
    ///   - surface: The decoration surface pointer
    ///   - windowID: The window this decoration belongs to
    ///   - area: Which decoration area this surface represents
    nonisolated func registerDecorationSurface(_ surface: OpaquePointer, windowID: WindowID, area: DecorationArea) {
        let surfaceID = UInt(bitPattern: surface)
        state.decorationSurfaces[surfaceID] = (windowID, area)
    }

    /// Unregister a decoration surface.
    ///
    /// SAFETY: nonisolated because it only modifies the state dictionary which is safe
    /// since all modifications happen on the main thread.
    ///
    /// - Parameter surface: The decoration surface to unregister
    nonisolated func unregisterDecorationSurface(_ surface: OpaquePointer) {
        let surfaceID = UInt(bitPattern: surface)
        state.decorationSurfaces.removeValue(forKey: surfaceID)
    }

    /// Lookup WindowID from wl_surface pointer.
    ///
    /// libdecor sets LuminaWindowUserData as surface user data, which contains
    /// the WindowID split into high/low UInt64 values. We reconstruct it here.
    ///
    /// SAFETY: This is nonisolated because it's called from Wayland input callbacks
    /// that run synchronously on the main thread during wl_display_dispatch().
    ///
    /// - Parameter surface: The wl_surface pointer
    /// - Returns: The WindowID, or nil if not a Lumina window
    nonisolated fileprivate func windowID(for surface: OpaquePointer?) -> WindowID? {
        guard let surface = surface else { return nil }

        // Get user data from surface (set by libdecor_decorate to LuminaWindowUserData)
        guard let userData = wl_surface_get_user_data(surface) else {
            return nil
        }

        // Cast to LuminaWindowUserData
        let windowData = userData.assumingMemoryBound(to: LuminaWindowUserData.self)

        // Reconstruct UUID from high/low UInt64 values (inverse of encoding in WaylandWindow.swift)
        let high = windowData.pointee.window_id_high
        let low = windowData.pointee.window_id_low

        var uuidBytes: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuidBytes) { ptr in
            ptr.storeBytes(of: high, toByteOffset: 0, as: UInt64.self)
            ptr.storeBytes(of: low, toByteOffset: 8, as: UInt64.self)
        }

        return WindowID(id: UUID(uuid: uuidBytes))
    }

    // MARK: - Event Queue Management

    /// Dequeue the next pending event.
    ///
    /// Called by WaylandApplication.pumpEvents() to retrieve translated events.
    ///
    /// - Returns: The next event, or nil if queue is empty
    func dequeueEvent() -> Event? {
        guard !state.eventQueue.isEmpty else { return nil }
        return state.eventQueue.removeFirst()
    }

    /// Enqueue a translated event for delivery to the application.
    ///
    /// SAFETY: This is nonisolated because it's called from Wayland input callbacks
    /// that run synchronously on the main thread during wl_display_dispatch().
    ///
    /// - Parameter event: The event to enqueue
    nonisolated internal func enqueueEvent(_ event: Event) {
        state.eventQueue.append(event)
    }

    // MARK: - Application Reference

    /// Set the application reference (called during initialization)
    func setApplication(_ app: WaylandApplication) {
        self.application = app
    }

    /// Restore the current cursor on pointer enter (matches GLFW behavior)
    ///
    /// SAFETY: nonisolated because called from C callbacks that run synchronously
    /// on main thread during wl_display_dispatch().
    nonisolated fileprivate func restoreCursorOnEnter() {
        guard let app = application else { return }

        let cursorState = app.cursorState

        // Don't restore cursor if it's hidden
        if cursorState.hidden {
            return
        }

        // Restore current cursor or default to arrow
        let cursorName = cursorState.currentName ?? "left_ptr"
        applyCursor(cursorName, app: app)
    }

    /// Handle click on decoration surface (initiate move or resize)
    ///
    /// SAFETY: nonisolated because called from C callbacks that run synchronously
    /// on main thread during wl_display_dispatch().
    nonisolated fileprivate func handleDecorationClick(windowID: WindowID, area: DecorationArea, serial: UInt32) {
        guard let app = application,
              let seat = state.seat else {
            return
        }

        // Get the window's xdg_toplevel
        guard let window = app.waylandWindow(for: windowID),
              let toplevel = window.getToplevel() else {
            return
        }

        switch area {
        case .titleBar:
            // Title bar click initiates move
            xdg_toplevel_move(toplevel, seat, serial)

        case .topLeftCorner:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT.rawValue))
        case .topRightCorner:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT.rawValue))
        case .bottomLeftCorner:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT.rawValue))
        case .bottomRightCorner:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT.rawValue))

        case .leftBorder:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_LEFT.rawValue))
        case .rightBorder:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_RIGHT.rawValue))
        case .bottomBorder:
            xdg_toplevel_resize(toplevel, seat, serial, UInt32(XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM.rawValue))
        }
    }

    /// Get cursor name for decoration area
    ///
    /// Uses XDG cursor naming convention (same as GLFW).
    nonisolated fileprivate func cursorNameForDecorationArea(_ area: DecorationArea) -> String {
        switch area {
        case .titleBar:
            return "left_ptr"
        case .leftBorder:
            return "w-resize"
        case .rightBorder:
            return "e-resize"
        case .bottomBorder:
            return "s-resize"
        case .topLeftCorner:
            return "nw-resize"
        case .topRightCorner:
            return "ne-resize"
        case .bottomLeftCorner:
            return "sw-resize"
        case .bottomRightCorner:
            return "se-resize"
        }
    }

    /// Apply cursor to pointer (shared with WaylandCursor)
    ///
    /// SAFETY: nonisolated because called from C callbacks that run synchronously
    /// on main thread during wl_display_dispatch().
    nonisolated fileprivate func applyCursor(_ cursorName: String, app: WaylandApplication) {
        let appCursorState = app.cursorState

        // Don't apply cursor if it's hidden
        if appCursorState.hidden {
            return
        }

        guard let cursorSurface = appCursorState.surface,
              let pointer = state.pointer else {
            return
        }

        let cursorLoader = app.cursorLoader

        // Determine which theme to use based on buffer scale (default to 1 for global cursor)
        let theme = appCursorState.themeHiDPI ?? appCursorState.theme

        guard let theme = theme,
              let getCursor = cursorLoader.wl_cursor_theme_get_cursor,
              let getBuffer = cursorLoader.wl_cursor_image_get_buffer else {
            return
        }

        // Load cursor from theme
        guard let wlCursorPtr = cursorName.withCString({ getCursor(theme, $0) }) else {
            return
        }

        // Bind OpaquePointer to WlCursor structure
        let wlCursor = UnsafeRawPointer(wlCursorPtr)
            .assumingMemoryBound(to: WaylandCursorLoader.WlCursor.self)
            .pointee

        // Get first image from cursor (TODO: handle animated cursors)
        let imageCount = Int(wlCursor.image_count)
        guard imageCount > 0,
              let imagesPtr = wlCursor.images,
              let imagePtr = imagesPtr[0] else {
            return
        }

        // Get buffer for cursor image
        guard let buffer = getBuffer(imagePtr) else {
            return
        }

        // Bind image pointer to WlCursorImage structure
        let image = UnsafeRawPointer(imagePtr)
            .assumingMemoryBound(to: WaylandCursorLoader.WlCursorImage.self)
            .pointee

        // Apply cursor to surface
        let hotspotX = Int32(image.hotspot_x)
        let hotspotY = Int32(image.hotspot_y)

        wl_surface_attach(cursorSurface, buffer, 0, 0)
        wl_surface_damage(cursorSurface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(cursorSurface)

        // Set cursor on pointer (use serial from last enter event)
        let serial = state.pointerEnterSerial
        wl_pointer_set_cursor(pointer, serial, cursorSurface, hotspotX, hotspotY)
    }

    // MARK: - Seat Capability Handling

    /// Setup wl_seat listener to detect input device capabilities.
    ///
    /// This must be called when a wl_seat global is advertised by the compositor.
    ///
    /// SAFETY: This is nonisolated because it only sets up C callback pointers,
    /// which is safe from any thread. The callbacks themselves run on the main thread.
    ///
    /// - Parameter seat: The wl_seat object to listen to
    nonisolated func setupSeatListener(_ seat: OpaquePointer) {
        // CRITICAL: Listener struct is stored in State (not stack-allocated!)
        // Wayland holds a pointer to this struct, so it must remain alive
        // use static const structs; we store as instance variable
        let userData = Unmanaged.passUnretained(self).toOpaque()
        _ = withUnsafeMutablePointer(to: &state.seatListener) { listenerPtr in
            wl_seat_add_listener(seat, listenerPtr, userData)
        }
    }
}

// MARK: - Seat Callbacks

/// Seat capabilities callback (C function).
///
/// Called when the compositor advertises input device capabilities (pointer, keyboard, touch).
/// We initialize wl_pointer and wl_keyboard interfaces when available.
private func seatCapabilitiesCallback(
    data: UnsafeMutableRawPointer?,
    seat: OpaquePointer?,
    capabilities: UInt32
) {
    guard let data, let seat else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    // Store seat reference for move/resize operations
    inputState.state.seat = seat

    // Check for pointer capability
    if capabilities & WL_SEAT_CAPABILITY_POINTER.rawValue != 0 {
        if inputState.state.pointer == nil {
            guard let pointer = wl_seat_get_pointer(seat) else {
                logger.error("Failed to get wl_pointer interface")
                return
            }

            inputState.state.pointer = pointer
            inputState.setupPointerListener(pointer)
        }
    } else {
        // Pointer capability removed (rare but possible)
        if let pointer = inputState.state.pointer {
            wl_pointer_release(pointer)
            inputState.state.pointer = nil
        }
    }

    // Check for keyboard capability
    if capabilities & WL_SEAT_CAPABILITY_KEYBOARD.rawValue != 0 {
        if inputState.state.keyboard == nil {
            guard let keyboard = wl_seat_get_keyboard(seat) else {
                logger.error("Failed to get wl_keyboard interface")
                return
            }

            inputState.state.keyboard = keyboard
            inputState.setupKeyboardListener(keyboard)
        }
    } else {
        // Keyboard capability removed (rare but possible)
        if let keyboard = inputState.state.keyboard {
            wl_keyboard_release(keyboard)
            inputState.state.keyboard = nil
        }
    }
}

/// Seat name callback (C function).
///
/// Called when the compositor provides a name for the seat (informational only).
private func seatNameCallback(
    data: UnsafeMutableRawPointer?,
    seat: OpaquePointer?,
    name: UnsafePointer<CChar>?
) {
    // Informational only
}

// MARK: - Pointer Listener Setup

extension WaylandInputState {
    /// Setup wl_pointer listener for mouse/trackpad events.
    ///
    /// SAFETY: This is nonisolated because it only sets up C callback pointers,
    /// which is safe from any thread.
    ///
    /// - Parameter pointer: The wl_pointer object to listen to
    nonisolated fileprivate func setupPointerListener(_ pointer: OpaquePointer) {
        // CRITICAL: Listener struct is stored in State (not stack-allocated!)
        // Wayland holds a pointer to this struct, so it must remain alive
        let userData = Unmanaged.passUnretained(self).toOpaque()
        _ = withUnsafeMutablePointer(to: &state.pointerListener) { listenerPtr in
            wl_pointer_add_listener(pointer, listenerPtr, userData)
        }
    }
}

// MARK: - Pointer Callbacks

/// Pointer enter callback (C function).
///
/// Called when the pointer enters a surface.
private func pointerEnterCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    serial: UInt32,
    surface: OpaquePointer?,
    surfaceX: wl_fixed_t,
    surfaceY: wl_fixed_t
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    inputState.state.pointerSurface = surface
    inputState.state.pointerEnterSerial = serial  // Store serial for cursor operations

    // Convert fixed-point to float
    inputState.state.pointerX = Float(wl_fixed_to_double(surfaceX))
    inputState.state.pointerY = Float(wl_fixed_to_double(surfaceY))

    // Check if this is a decoration surface
    let surfaceID = UInt(bitPattern: surface)
    if let decorationInfo = inputState.state.decorationSurfaces[surfaceID] {
        // Entering a client-side decoration surface
        inputState.state.pointerWindowID = decorationInfo.windowID
        inputState.state.pointerOnDecoration = decorationInfo.area

        // Set cursor based on decoration area
        if let app = inputState.application {
            let cursorName = inputState.cursorNameForDecorationArea(decorationInfo.area)
            inputState.applyCursor(cursorName, app: app)
        }
    } else {
        // Check if this is a surface we own (main window surface)
        if let windowID = inputState.windowID(for: surface) {
            // Check if this is the main content surface (like GLFW does)
            let isMainSurface = inputState.state.windowMainSurfaces[windowID] == surface

            // Entering window surface
            inputState.state.pointerWindowID = windowID
            inputState.state.pointerOnDecoration = nil
            inputState.state.pointerOnMainSurface = isMainSurface  // Track main surface state

            // Only send entered event for main surface
            if isMainSurface {
                // DON'T restore cursor automatically - let libdecor/compositor handle it
                // (SSD mode: compositor sets resize cursors on main surface edges)

                let position = LogicalPosition(x: inputState.state.pointerX, y: inputState.state.pointerY)
                inputState.enqueueEvent(.pointer(.entered(windowID, position: position)))
            }
        }
        // else: Unknown surface - don't touch cursor
    }
}

/// Pointer leave callback (C function).
///
/// Called when the pointer leaves a surface.
private func pointerLeaveCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    serial: UInt32,
    surface: OpaquePointer?
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    // Only send leave event for main window surface (not decorations)
    if inputState.state.pointerOnMainSurface {
        if let windowID = inputState.windowID(for: surface) {
            // Use last known pointer position when leaving
            let position = LogicalPosition(x: inputState.state.pointerX, y: inputState.state.pointerY)
            inputState.enqueueEvent(.pointer(.left(windowID, position: position)))
        }
    }

    inputState.state.pointerSurface = nil
    inputState.state.pointerWindowID = nil
    inputState.state.pointerOnDecoration = nil
    inputState.state.pointerOnMainSurface = false  // Clear main surface flag
}

/// Pointer motion callback (C function).
///
/// Called when the pointer moves within a surface.
/// Motion events are coalesced and delivered in the frame callback.
private func pointerMotionCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    time: UInt32,
    surfaceX: wl_fixed_t,
    surfaceY: wl_fixed_t
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    // Convert fixed-point to float
    inputState.state.pointerX = Float(wl_fixed_to_double(surfaceX))
    inputState.state.pointerY = Float(wl_fixed_to_double(surfaceY))
    inputState.state.hasPendingMotion = true
}

/// Pointer button callback (C function).
///
/// Called when a mouse button is pressed or released.
private func pointerButtonCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    serial: UInt32,
    time: UInt32,
    button: UInt32,
    state: UInt32
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    guard let windowID = inputState.state.pointerWindowID else { return }

    // Check if button press is on a decoration surface
    if let decorationArea = inputState.state.pointerOnDecoration {
        let pressed = (state == WL_POINTER_BUTTON_STATE_PRESSED.rawValue)

        // Only handle left button on decorations
        if button == 0x110 && pressed {  // BTN_LEFT
            // Handle decoration click (move or resize)
            inputState.handleDecorationClick(windowID: windowID, area: decorationArea, serial: serial)
        }
        return  // Don't send button events for decoration surfaces
    }

    // Only send button events if we're on the main content surface (like GLFW)
    // This filters out button events from libdecor-created subsurfaces
    if !inputState.state.pointerOnMainSurface {
        return
    }

    // Translate Wayland button codes to MouseButton
    // Linux input event codes (from linux/input-event-codes.h):
    // BTN_LEFT = 0x110, BTN_RIGHT = 0x111, BTN_MIDDLE = 0x112, BTN_SIDE = 0x113, BTN_EXTRA = 0x114, etc.
    let mouseButton: MouseButton?
    switch button {
    case 0x110: // BTN_LEFT
        mouseButton = .left
    case 0x111: // BTN_RIGHT
        mouseButton = .right
    case 0x112: // BTN_MIDDLE
        mouseButton = .middle
    case 0x113: // BTN_SIDE (typically "back")
        mouseButton = .button4
    case 0x114: // BTN_EXTRA (typically "forward")
        mouseButton = .button5
    case 0x115: // BTN_FORWARD
        mouseButton = .button6
    case 0x116: // BTN_BACK
        mouseButton = .button7
    case 0x117: // BTN_TASK
        mouseButton = .button8
    default:
        mouseButton = nil
    }

    guard let mouseButton = mouseButton else { return }

    let position = LogicalPosition(x: inputState.state.pointerX, y: inputState.state.pointerY)
    let modifiers = inputState.state.modifiers
    let pressed = (state == WL_POINTER_BUTTON_STATE_PRESSED.rawValue)

    if pressed {
        inputState.enqueueEvent(.pointer(.buttonPressed(windowID, button: mouseButton, position: position, modifiers: modifiers)))
    } else {
        inputState.enqueueEvent(.pointer(.buttonReleased(windowID, button: mouseButton, position: position, modifiers: modifiers)))
    }
}

/// Pointer axis callback (C function).
///
/// Called when the mouse wheel or trackpad is scrolled.
private func pointerAxisCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    time: UInt32,
    axis: UInt32,
    value: wl_fixed_t
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    guard let windowID = inputState.state.pointerWindowID else { return }

    // Only send scroll events if we're on the main surface (like GLFW)
    guard inputState.state.pointerOnMainSurface else { return }

    // Convert fixed-point to float (Wayland uses 1/256 of a pixel per unit)
    let delta = Float(wl_fixed_to_double(value))

    // Normalize to Lumina scroll units (pixels)
    let normalizedDelta = delta / 10.0

    if axis == WL_POINTER_AXIS_VERTICAL_SCROLL.rawValue {
        inputState.enqueueEvent(.pointer(.wheel(windowID, deltaX: 0.0, deltaY: normalizedDelta)))
    } else if axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL.rawValue {
        inputState.enqueueEvent(.pointer(.wheel(windowID, deltaX: normalizedDelta, deltaY: 0.0)))
    }
}

/// Pointer frame callback (C function).
///
/// Called to group related pointer events together.
/// We use this to coalesce motion events for efficiency.
private func pointerFrameCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    // Deliver coalesced motion event (only for main surface, like GLFW)
    if inputState.state.hasPendingMotion,
       let windowID = inputState.state.pointerWindowID,
       inputState.state.pointerOnMainSurface {
        let position = LogicalPosition(x: inputState.state.pointerX, y: inputState.state.pointerY)
        inputState.enqueueEvent(.pointer(.moved(windowID, position: position)))
        inputState.state.hasPendingMotion = false
    }
}

/// Pointer axis source callback (C function).
///
/// Called to indicate the source of an axis event (wheel, finger, continuous).
private func pointerAxisSourceCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    axisSource: UInt32
) {
    // Not used yet - could distinguish wheel vs trackpad scrolling
}

/// Pointer axis stop callback (C function).
///
/// Called when an axis event ends (e.g., finger lifted from trackpad).
private func pointerAxisStopCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    time: UInt32,
    axis: UInt32
) {
    // Not used yet - could support scroll momentum
}

/// Pointer axis discrete callback (C function).
///
/// Called for discrete scroll events (e.g., mouse wheel clicks).
private func pointerAxisDiscreteCallback(
    data: UnsafeMutableRawPointer?,
    pointer: OpaquePointer?,
    axis: UInt32,
    discrete: Int32
) {
    // Not used yet - could provide discrete scroll counts
}

// MARK: - Keyboard Listener Setup

extension WaylandInputState {
    /// Setup wl_keyboard listener for keyboard events.
    ///
    /// SAFETY: This is nonisolated because it only sets up C callback pointers,
    /// which is safe from any thread.
    ///
    /// - Parameter keyboard: The wl_keyboard object to listen to
    nonisolated fileprivate func setupKeyboardListener(_ keyboard: OpaquePointer) {
        // CRITICAL: Listener struct is stored in State (not stack-allocated!)
        // Wayland holds a pointer to this struct, so it must remain alive
        let userData = Unmanaged.passUnretained(self).toOpaque()
        _ = withUnsafeMutablePointer(to: &state.keyboardListener) { listenerPtr in
            wl_keyboard_add_listener(keyboard, listenerPtr, userData)
        }
    }
}

// MARK: - Keyboard Callbacks

/// Keyboard keymap callback (C function).
///
/// Called when the compositor provides the keyboard layout (XKB keymap).
/// This is essential for proper key code interpretation and text generation.
private func keyboardKeymapCallback(
    data: UnsafeMutableRawPointer?,
    keyboard: OpaquePointer?,
    format: UInt32,
    fd: Int32,
    size: UInt32
) {
    guard let data = data else {
        close(fd)
        return
    }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    defer { close(fd) }

    // Verify format is XKB v1
    guard format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1.rawValue else {
        logger.error("Unsupported keymap format: \(format)")
        return
    }

    guard let xkbContext = inputState.xkbContext else {
        logger.error("Cannot load keymap - XKB context not initialized")
        return
    }

    // mmap the keymap file
    let mapSize = Int(size)
    guard let map = mmap(nil, mapSize, PROT_READ, MAP_PRIVATE, fd, 0),
          map != MAP_FAILED else {
        logger.error("Failed to mmap keymap: errno \(errno)")
        return
    }

    defer { munmap(map, mapSize) }

    // Create XKB keymap from the mmap'd string
    guard let keymap = xkb_keymap_new_from_string(
        xkbContext,
        map.assumingMemoryBound(to: CChar.self),
        XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS
    ) else {
        logger.error("Failed to create XKB keymap")
        return
    }

    // Release old keymap and state if present
    if let oldState = inputState.state.xkbState {
        xkb_state_unref(oldState)
        inputState.state.xkbState = nil
    }

    if let oldKeymap = inputState.state.xkbKeymap {
        xkb_keymap_unref(oldKeymap)
    }

    // Create new XKB state from keymap
    guard let state = xkb_state_new(keymap) else {
        logger.error("Failed to create XKB state")
        xkb_keymap_unref(keymap)
        return
    }

    inputState.state.xkbKeymap = keymap
    inputState.state.xkbState = state
}

/// Keyboard enter callback (C function).
///
/// Called when a surface gains keyboard focus.
private func keyboardEnterCallback(
    data: UnsafeMutableRawPointer?,
    keyboard: OpaquePointer?,
    serial: UInt32,
    surface: OpaquePointer?,
    keys: UnsafeMutablePointer<wl_array>?
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    if let windowID = inputState.windowID(for: surface) {
        inputState.state.focusedWindowID = windowID
        inputState.enqueueEvent(.window(.focused(windowID)))
    }
}

/// Keyboard leave callback (C function).
///
/// Called when a surface loses keyboard focus.
private func keyboardLeaveCallback(
    data: UnsafeMutableRawPointer?,
    keyboard: OpaquePointer?,
    serial: UInt32,
    surface: OpaquePointer?
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    if let windowID = inputState.windowID(for: surface) {
        inputState.enqueueEvent(.window(.unfocused(windowID)))
    }

    inputState.state.focusedWindowID = nil
}

/// Keyboard key callback (C function).
///
/// Called when a key is pressed or released.
private func keyboardKeyCallback(
    data: UnsafeMutableRawPointer?,
    keyboard: OpaquePointer?,
    serial: UInt32,
    time: UInt32,
    key: UInt32,
    state: UInt32
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    guard let windowID = inputState.state.focusedWindowID else { return }

    // Wayland sends Linux evdev key codes, XKB expects keycode + 8
    let xkbKeycode = key + 8

    let pressed = (state == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue)

    // Extract modifiers from XKB state
    let modifiers = inputState.extractModifiers()

    // Create KeyCode (using raw evdev key code)
    let keyCode = KeyCode(rawValue: key)

    // Update XKB state for key press/release
    if let xkbState = inputState.state.xkbState {
        let direction = pressed ? XKB_KEY_DOWN : XKB_KEY_UP
        xkb_state_update_key(xkbState, xkbKeycode, direction)
    }

    // Enqueue key event
    if pressed {
        inputState.enqueueEvent(.keyboard(.keyDown(windowID, key: keyCode, modifiers: modifiers)))

        // Generate text input for character keys (only on press)
        if let text = inputState.generateTextInput(xkbKeycode: xkbKeycode), !text.isEmpty {
            inputState.enqueueEvent(.keyboard(.textInput(windowID, text: text)))
        }
    } else {
        inputState.enqueueEvent(.keyboard(.keyUp(windowID, key: keyCode, modifiers: modifiers)))
    }
}

/// Keyboard modifiers callback (C function).
///
/// Called when modifier key state changes (Shift, Ctrl, Alt, Super).
private func keyboardModifiersCallback(
    data: UnsafeMutableRawPointer?,
    keyboard: OpaquePointer?,
    serial: UInt32,
    modsDepressed: UInt32,
    modsLatched: UInt32,
    modsLocked: UInt32,
    group: UInt32
) {
    guard let data = data else { return }

    let inputState = Unmanaged<WaylandInputState>.fromOpaque(data).takeUnretainedValue()

    // Update XKB state with compositor-provided modifier state
    if let xkbState = inputState.state.xkbState {
        xkb_state_update_mask(
            xkbState,
            modsDepressed,
            modsLatched,
            modsLocked,
            0, 0,
            group
        )

        // Update our modifier keys state by checking XKB state
        var modifiers: ModifierKeys = []

        if xkb_state_mod_name_is_active(xkbState, "Shift", XKB_STATE_MODS_EFFECTIVE) == 1 {
            modifiers.insert(.shift)
        }
        if xkb_state_mod_name_is_active(xkbState, "Control", XKB_STATE_MODS_EFFECTIVE) == 1 {
            modifiers.insert(.control)
        }
        if xkb_state_mod_name_is_active(xkbState, "Mod1", XKB_STATE_MODS_EFFECTIVE) == 1 {  // Alt
            modifiers.insert(.alt)
        }
        if xkb_state_mod_name_is_active(xkbState, "Mod4", XKB_STATE_MODS_EFFECTIVE) == 1 {  // Super/Command
            modifiers.insert(.command)
        }

        inputState.state.modifiers = modifiers
    }
}

/// Keyboard repeat info callback (C function).
///
/// Called to configure key repeat rate and delay.
private func keyboardRepeatInfoCallback(
    data: UnsafeMutableRawPointer?,
    keyboard: OpaquePointer?,
    rate: Int32,
    delay: Int32
) {
    // Not used yet - key repeat is handled by compositor
    // Could implement client-side key repeat in the future
}

// MARK: - XKB Helper Methods

extension WaylandInputState {
    /// Extract current modifier key state from XKB state.
    ///
    /// SAFETY: This is nonisolated because it only reads from the @unchecked Sendable
    /// state wrapper, which is safe since all mutations happen on main thread.
    ///
    /// - Returns: ModifierKeys bitfield representing active modifiers
    nonisolated fileprivate func extractModifiers() -> ModifierKeys {
        guard let xkbState = state.xkbState else {
            return []
        }

        var modifiers: ModifierKeys = []

        // Check Shift
        if xkb_state_mod_name_is_active(xkbState, "Shift", XKB_STATE_MODS_EFFECTIVE) != 0 {
            modifiers.insert(.shift)
        }

        // Check Control
        if xkb_state_mod_name_is_active(xkbState, "Control", XKB_STATE_MODS_EFFECTIVE) != 0 {
            modifiers.insert(.control)
        }

        // Check Alt (Mod1)
        if xkb_state_mod_name_is_active(xkbState, "Mod1", XKB_STATE_MODS_EFFECTIVE) != 0 {
            modifiers.insert(.alt)
        }

        // Check Super (Mod4)
        if xkb_state_mod_name_is_active(xkbState, "Mod4", XKB_STATE_MODS_EFFECTIVE) != 0 {
            modifiers.insert(.command)
        }

        return modifiers
    }

    /// Generate text input from XKB keycode.
    ///
    /// Uses XKB state to interpret the keycode according to the current keyboard layout,
    /// producing a UTF-8 string representing the character(s) typed.
    ///
    /// SAFETY: This is nonisolated because it only reads from the @unchecked Sendable
    /// state wrapper, which is safe since all mutations happen on main thread.
    ///
    /// - Parameter xkbKeycode: The XKB keycode (evdev keycode + 8)
    /// - Returns: UTF-8 text string, or nil if no text should be generated
    nonisolated fileprivate func generateTextInput(xkbKeycode: UInt32) -> String? {
        guard let xkbState = state.xkbState else {
            return nil
        }

        // Get the keysym for this key
        let keysym = xkb_state_key_get_one_sym(xkbState, xkbKeycode)

        // Skip if this is a control key (no text output)
        // XKB keysyms < 0x100 are ISO Latin-1, >= 0x100 are special keys
        guard keysym >= 0x20 else {
            return nil
        }

        // Convert keysym to UTF-8 string
        var buffer = [CChar](repeating: 0, count: 64)
        let count = xkb_state_key_get_utf8(xkbState, xkbKeycode, &buffer, buffer.count)

        guard count > 0 else {
            return nil
        }

        // Convert buffer to String using proper decoding (truncating null terminator)
        let bytes = buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - Logger

/// Logger instance for Wayland input events.
private let logger = LuminaLogger(label: "lumina.wayland.input", level: .info)

#endif // os(Linux) && LUMINA_WAYLAND
