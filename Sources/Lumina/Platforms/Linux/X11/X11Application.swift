#if os(Linux)
import CXCBLinux
import Foundation
import Glibc  // For free()

/// Thread-safe event queue for all events (user + platform events from wait())
private final class EventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Event] = []

    func append(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func removeFirst() -> Event? {
        lock.lock()
        defer { lock.unlock() }
        return events.isEmpty ? nil : events.removeFirst()
    }
}

/// X11/XCB implementation of LuminaApp.
///
/// This implementation provides a Linux X11 backend using XCB (X protocol C-Binding)
/// for window management and event processing. It handles:
/// - Event loop with wait/poll/waitUntil modes
/// - Window registry for event routing
/// - XKB keyboard support via libxkbcommon
/// - Thread-safe user event posting
///
/// **Architecture:**
/// - Borrows XCB connection from X11Platform
/// - Platform owns the connection and screen
/// - Application manages windows and event loop
///
/// **Internal:** Only X11Platform can create applications.
///
/// Example:
/// ```swift
/// #if os(Linux)
/// let platform = try X11Platform()
/// var app = try platform.createApp()
/// let window = try app.createWindow(
///     title: "Hello X11",
///     size: LogicalSize(width: 800, height: 600),
///     resizable: true,
///     monitor: nil
/// ).get()
/// window.show()
/// try app.run()
/// #endif
/// ```
@MainActor
final class X11Application: LuminaApp {
    public typealias Window = X11Window

    // MARK: - Platform Reference

    /// Strong reference to platform (keeps it alive)
    ///
    /// The platform owns the XCB connection and must outlive the app.
    /// This strong reference ensures proper lifetime management.
    private let platform: X11Platform

    /// Cached X11 atoms for window manager communication
    private let atoms: X11Atoms

    /// XKB context for keyboard handling
    private let xkbContext: OpaquePointer?

    /// XKB device ID
    private let xkbDeviceID: Int32

    /// XKB state for keyboard event translation
    private let xkbState: OpaquePointer?

    /// Logger for X11 platform operations
    private let logger: LuminaLogger

    /// Event queue for all events (user events + platform events from wait())
    private let eventQueue = EventQueue()

    /// Window registry (xcb_window_t -> WindowID)
    private var windowRegistry = WindowRegistry<UInt32>()

    /// Track window geometry to detect move vs resize
    private var windowGeometry: [UInt32: (x: Int16, y: Int16, width: UInt16, height: UInt16)] = [:]

    /// Whether the application should quit
    private var shouldQuit: Bool = false

    /// Whether to exit when last window closes
    var exitOnLastWindowClosed: Bool = true

    /// Callback invoked when a window is closed
    private var onWindowClosed: WindowCloseCallback?

    /// Initialize X11 application from platform.
    ///
    /// The platform provides the XCB connection and screen.
    /// This initialization performs:
    /// 1. Cache required X11 atoms
    /// 2. Initialize XKB for keyboard support
    ///
    /// **Internal:** Only X11Platform can create applications.
    ///
    /// - Parameter platform: The X11Platform that owns the connection
    /// - Throws: `LuminaError.platformError` if X11 initialization fails
    init(platform: X11Platform) throws {
        self.platform = platform

        // Initialize logger first
        self.logger = LuminaLogger.makeLogger(label: "lumina.x11")
        logger.info("Initializing X11 application from platform")

        // Access platform resources
        let connection = platform.xcbConnection

        // Cache atoms
        do {
            logger.debug("Caching X11 atoms")
            self.atoms = try X11Atoms.cache(connection: connection)
            logger.debug("X11 atoms cached successfully")
        } catch {
            logger.error("Failed to cache X11 atoms: \(error)")
            throw error
        }

        // Initialize XKB for keyboard support
        logger.debug("xkb_context_new()")
        let XKB_CONTEXT_NO_FLAGS = xkb_context_flags(rawValue: 0)
        guard let xkbCtx = xkb_context_new(XKB_CONTEXT_NO_FLAGS) else {
            logger.error("Failed to create XKB context")
            throw LuminaError.platformError(
                platform: "Linux/X11",
                operation: "xkb_context_new",
                code: -1,
                message: "Failed to create XKB context"
            )
        }
        self.xkbContext = xkbCtx
        logger.debug("XKB context created successfully")

        // Setup XKB extension
        let xkbMajor: UInt16 = 1
        let xkbMinor: UInt16 = 0
        logger.debug("xkb_x11_setup_xkb_extension(v\(xkbMajor).\(xkbMinor))")
        let setupResult = xkb_x11_setup_xkb_extension(
            connection,
            xkbMajor,
            xkbMinor,
            XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS,
            nil, nil, nil, nil
        )

        guard setupResult != 0 else {
            logger.error("XKB extension setup failed")
            xkb_context_unref(xkbCtx)
            throw LuminaError.x11ExtensionMissing(extension: "XKB extension (xkb_x11_setup_xkb_extension failed)")
        }
        logger.debug("XKB extension available: v\(xkbMajor).\(xkbMinor)")

        // Get XKB device ID
        logger.debug("xkb_x11_get_core_keyboard_device_id()")
        self.xkbDeviceID = xkb_x11_get_core_keyboard_device_id(connection)
        guard xkbDeviceID != -1 else {
            logger.error("Failed to get XKB core keyboard device")
            xkb_context_unref(xkbCtx)
            throw LuminaError.x11ExtensionMissing(extension: "XKB core keyboard device")
        }
        logger.debug("XKB device ID: \(xkbDeviceID)")

        // Create XKB keymap and state from X11 device
        logger.debug("xkb_x11_keymap_new_from_device()")
        let XKB_KEYMAP_COMPILE_NO_FLAGS = xkb_keymap_compile_flags(rawValue: 0)
        guard let keymap = xkb_x11_keymap_new_from_device(xkbCtx, connection, xkbDeviceID, XKB_KEYMAP_COMPILE_NO_FLAGS) else {
            logger.error("Failed to create XKB keymap")
            xkb_context_unref(xkbCtx)
            throw LuminaError.platformError(
                platform: "Linux/X11",
                operation: "xkb_x11_keymap_new_from_device",
                code: -1,
                message: "Failed to create XKB keymap"
            )
        }

        logger.debug("xkb_x11_state_new_from_device()")
        guard let state = xkb_x11_state_new_from_device(keymap, connection, xkbDeviceID) else {
            logger.error("Failed to create XKB state")
            xkb_keymap_unref(keymap)
            xkb_context_unref(xkbCtx)
            throw LuminaError.platformError(
                platform: "Linux/X11",
                operation: "xkb_x11_state_new_from_device",
                code: -1,
                message: "Failed to create XKB state"
            )
        }

        self.xkbState = state
        xkb_keymap_unref(keymap)  // State keeps a reference, safe to unref
        logger.debug("XKB keymap and state initialized successfully")

        // Flush connection to ensure all setup requests are sent
        logger.debug("xcb_flush()")
        _ = xcb_flush_shim(connection)

        logger.info("X11 application initialized successfully")
    }

    func run() throws {
        shouldQuit = false
        logger.info("Event loop started: mode = run (blocking)")

        while !shouldQuit {
            // Block waiting for events
            if let event = pumpEvents(mode: .wait) {
                // Event was processed, continue
                _ = event
            }
        }

        logger.info("Event loop exited")
    }

    func poll() throws -> Event? {
        return pumpEvents(mode: .poll)
    }

    func wait() throws {
        // Block until an event arrives, then queue it for poll() to retrieve
        if let event = pumpEvents(mode: .wait) {
            eventQueue.append(event)
        }
    }

    func pumpEvents(mode: ControlFlowMode) -> Event? {
        logger.debug("pumpEvents: mode = \(mode)")

        let connection = platform.xcbConnection

        // Check if we have queued events first (from wait() or postUserEvent)
        if let queuedEvent = eventQueue.removeFirst() {
            return queuedEvent
        }

        // Fetch and translate one XCB event based on control flow mode
        switch mode {
        case .wait:
            // Block until an event arrives
            if let xcbEvent = xcb_wait_for_event(connection) {
                defer { free(xcbEvent) }
                if let event = translateXCBEvent(xcbEvent) {
                    return event
                }
            }

        case .poll:
            // Non-blocking: poll one event
            if let xcbEvent = xcb_poll_for_event(connection) {
                defer { free(xcbEvent) }
                if let event = translateXCBEvent(xcbEvent) {
                    return event
                }
            }

        case .waitUntil(let deadline):
            // Block with timeout using select()
            let fd = xcb_get_file_descriptor_shim(connection)
            let timeoutSeconds = deadline.date.timeIntervalSinceNow

            if timeoutSeconds > 0 {
                var timeout = timeval(
                    tv_sec: Int(timeoutSeconds),
                    tv_usec: Int((timeoutSeconds.truncatingRemainder(dividingBy: 1.0)) * 1_000_000)
                )

                var readfds = fd_set()
                fdZero(&readfds)
                fdSet(fd, &readfds)

                let result = select(fd + 1, &readfds, nil, nil, &timeout)

                if result > 0 {
                    // Events available, poll one
                    if let xcbEvent = xcb_poll_for_event(connection) {
                        defer { free(xcbEvent) }
                        if let event = translateXCBEvent(xcbEvent) {
                            return event
                        }
                    }
                }
            } else {
                // Deadline expired, just poll once
                if let xcbEvent = xcb_poll_for_event(connection) {
                    defer { free(xcbEvent) }
                    if let event = translateXCBEvent(xcbEvent) {
                        return event
                    }
                }
            }
        }

        return nil
    }

    /// Translate XCB event to Lumina event.
    private func translateXCBEvent(_ xcbEvent: UnsafeMutablePointer<xcb_generic_event_t>) -> Event? {
        let responseType = xcb_event_response_type_shim(xcbEvent) & 0x7f

        switch Int32(responseType) {
        case XCB_EXPOSE:
            return xcbEvent.withMemoryRebound(to: xcb_expose_event_t.self, capacity: 1) { ptr in
                windowRegistry.windowID(for: ptr.pointee.window).map { .redraw(.requested($0, dirtyRect: nil)) }
            }

        case XCB_CONFIGURE_NOTIFY:
            return xcbEvent.withMemoryRebound(to: xcb_configure_notify_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.window) else { return nil }

                let newGeometry = (x: ptr.pointee.x, y: ptr.pointee.y, width: ptr.pointee.width, height: ptr.pointee.height)
                let oldGeometry = windowGeometry[ptr.pointee.window]

                // Update stored geometry
                windowGeometry[ptr.pointee.window] = newGeometry

                // Determine what changed
                let positionChanged = oldGeometry.map { $0.x != newGeometry.x || $0.y != newGeometry.y } ?? false
                let sizeChanged = oldGeometry.map { $0.width != newGeometry.width || $0.height != newGeometry.height } ?? true

                // Prefer resize events over move events if both changed
                if sizeChanged {
                    return .window(.resized(windowID, LogicalSize(width: Float(newGeometry.width), height: Float(newGeometry.height))))
                } else if positionChanged {
                    return .window(.moved(windowID, LogicalPosition(x: Float(newGeometry.x), y: Float(newGeometry.y))))
                }

                return nil
            }

        case XCB_BUTTON_PRESS:
            return xcbEvent.withMemoryRebound(to: xcb_button_press_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                return X11Input.translateScrollEvent(xcbEvent, windowID: windowID).map { .pointer($0) }
                    ?? X11Input.translateButtonEvent(xcbEvent, windowID: windowID, pressed: true).map { .pointer($0) }
            }

        case XCB_BUTTON_RELEASE:
            return xcbEvent.withMemoryRebound(to: xcb_button_release_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                return X11Input.translateButtonEvent(xcbEvent, windowID: windowID, pressed: false).map { .pointer($0) }
            }

        case XCB_MOTION_NOTIFY:
            return xcbEvent.withMemoryRebound(to: xcb_motion_notify_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                return X11Input.translateMotionEvent(xcbEvent, windowID: windowID).map { .pointer($0) }
            }

        case XCB_ENTER_NOTIFY:
            return xcbEvent.withMemoryRebound(to: xcb_enter_notify_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                let position = LogicalPosition(
                    x: Float(ptr.pointee.event_x),
                    y: Float(ptr.pointee.event_y)
                )
                return .pointer(.entered(windowID, position: position))
            }

        case XCB_LEAVE_NOTIFY:
            return xcbEvent.withMemoryRebound(to: xcb_leave_notify_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                let position = LogicalPosition(
                    x: Float(ptr.pointee.event_x),
                    y: Float(ptr.pointee.event_y)
                )
                return .pointer(.left(windowID, position: position))
            }

        case XCB_FOCUS_IN:
            return xcbEvent.withMemoryRebound(to: xcb_focus_in_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                logger.info("Window focused: id = \(windowID)")
                return .window(.focused(windowID))
            }

        case XCB_FOCUS_OUT:
            return xcbEvent.withMemoryRebound(to: xcb_focus_out_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                logger.info("Window unfocused: id = \(windowID)")
                return .window(.unfocused(windowID))
            }

        case XCB_CLIENT_MESSAGE:
            return xcbEvent.withMemoryRebound(to: xcb_client_message_event_t.self, capacity: 1) { ptr in
                guard ptr.pointee.type == atoms.WM_PROTOCOLS else { return nil }
                let data = withUnsafeBytes(of: ptr.pointee.data) { $0.load(as: xcb_atom_t.self) }
                guard data == atoms.WM_DELETE_WINDOW else { return nil }
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.window) else { return nil }

                logger.info("Window close requested: id = \(windowID)")
                logger.debug("xcb_destroy_window()")
                xcb_destroy_window(platform.xcbConnection, ptr.pointee.window)
                _ = xcb_flush_shim(platform.xcbConnection)
                windowRegistry.unregister(ptr.pointee.window)
                onWindowClosed?(windowID)

                if exitOnLastWindowClosed && windowRegistry.isEmpty {
                    logger.info("Last window closed, quitting application")
                    shouldQuit = true
                }

                logger.info("Window closed: id = \(windowID)")
                return .window(.closed(windowID))
            }

        case XCB_KEY_PRESS:
            return xcbEvent.withMemoryRebound(to: xcb_key_press_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }

                // Generate text input event if this key produces text, and queue it for next poll()
                if let textEvent = X11Input.translateTextInput(xcbEvent, windowID: windowID, xkbState: xkbState) {
                    eventQueue.append(.keyboard(textEvent))
                }

                // Return the key down event
                return X11Input.translateKeyEvent(xcbEvent, windowID: windowID, pressed: true, xkbState: xkbState).map { .keyboard($0) }
            }

        case XCB_KEY_RELEASE:
            return xcbEvent.withMemoryRebound(to: xcb_key_release_event_t.self, capacity: 1) { ptr in
                guard let windowID = windowRegistry.windowID(for: ptr.pointee.event) else { return nil }
                return X11Input.translateKeyEvent(xcbEvent, windowID: windowID, pressed: false, xkbState: xkbState).map { .keyboard($0) }
            }

        default:
            return nil
        }
    }

    nonisolated func postUserEvent(_ event: UserEvent) {
        eventQueue.append(.user(event))
        // TODO: Wake up event loop if blocked (requires pipe or similar mechanism)
    }

    func quit() {
        shouldQuit = true
    }

    func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> X11Window {
        logger.info("Creating window: title = '\(title)', size = \(size), resizable = \(resizable)")

        let window = try X11Window.create(
            connection: platform.xcbConnection,
            screen: platform.xcbScreen,
            atoms: atoms,
            title: title,
            size: size,
            resizable: resizable
        )

        // Register window in registry
        windowRegistry.register(window.xcbWindow, id: window.id)
        logger.info("Window created successfully: id = \(window.id), xcbWindow = \(window.xcbWindow)")

        return window
    }
}

// MARK: - Helper functions for fd_set manipulation

private func fdZero(_ set: inout fd_set) {
    #if arch(x86_64) || arch(arm64)
    set.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    #else
    set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    #endif
}

private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    let mask = Int32(1 << bitOffset)

    #if arch(x86_64) || arch(arm64)
    withUnsafeMutableBytes(of: &set.__fds_bits) { bytes in
        let ints = bytes.bindMemory(to: Int32.self)
        ints[intOffset] |= mask
    }
    #else
    withUnsafeMutableBytes(of: &set.fds_bits) { bytes in
        let ints = bytes.bindMemory(to: Int32.self)
        ints[intOffset] |= mask
    }
    #endif
}

#endif
