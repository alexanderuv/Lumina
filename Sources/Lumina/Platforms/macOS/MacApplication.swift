#if os(macOS)
import AppKit
import Foundation


/// macOS implementation of PlatformApp using AppKit.
///
/// This implementation wraps NSApplication's event loop and provides
/// Lumina's cross-platform event loop interface. It handles NSEvent
/// translation, user event queuing, and low-power wait modes.
/// App delegate to handle automatic termination when last window closes
@MainActor
private final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var exitOnLastWindowClosed: Bool = true

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return exitOnLastWindowClosed
    }
}

/// Thread-safe user event queue
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

/// Thread-safe window event queue
private final class WindowEventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [WindowEvent] = []

    func append(_ event: WindowEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func removeAll() -> [WindowEvent] {
        lock.lock()
        defer { lock.unlock() }
        let allEvents = events
        events.removeAll()
        return allEvents
    }
}

/// macOS implementation of LuminaApp.
///
/// **Do not instantiate this type directly.** Use `LuminaApp.create()` instead.
///
/// This type is public only because Swift requires it for protocol extensions.
/// It should be treated as an implementation detail.
@MainActor
public final class MacApplication: LuminaApp {
    public typealias Window = MacWindow
    private var shouldQuit: Bool = false
    private let userEventQueue = UserEventQueue()
    private let windowEventQueue = WindowEventQueue()
    private var windowRegistry = WindowRegistry<Int>()  // NSWindow.windowNumber -> WindowID
    private var onWindowClosed: WindowCloseCallback?
    private let appDelegate: MacAppDelegate

    /// Logger for macOS platform operations
    private let logger: LuminaLogger

    /// Track pointer enter/exit state per window to deduplicate events.
    /// AppKit can generate duplicate mouseEntered/mouseExited events.
    private var pointerInsideWindow: [WindowID: Bool] = [:]

    /// Windows that need redrawing
    private var redrawRequests: Set<WindowID> = []

    /// Display link for frame pacing (not yet implemented for M1)
    private var displayLink: AnyObject? = nil

    /// Last clipboard change count for hasChanged tracking
    private var lastChangeCount: Int = 0

    /// Strong reference to platform for lifetime management
    /// Platform must outlive the application
    private let platform: MacPlatform

    /// Whether the application should quit when the last window is closed.
    public var exitOnLastWindowClosed: Bool {
        get { appDelegate.exitOnLastWindowClosed }
        set { appDelegate.exitOnLastWindowClosed = newValue }
    }

    init(platform: MacPlatform) throws {
        // Store platform reference for lifetime management
        self.platform = platform
        // Initialize logger
        self.logger = LuminaLogger.makeLogger(label: "com.lumina.macos")
        logger.logInfo("Initializing macOS application")

        // Ensure NSApplication is initialized
        _ = NSApplication.shared
        logger.logPlatformCall("NSApplication.shared")

        // Create and set app delegate
        let delegate = MacAppDelegate()
        self.appDelegate = delegate
        if NSApp.delegate == nil {
            NSApp.delegate = delegate
        }

        // Set activation policy to regular app (shows in Dock)
        NSApp.setActivationPolicy(.regular)
        logger.logPlatformCall("NSApplication.setActivationPolicy(.regular)")

        // Create a standard application menu with Quit support
        setupApplicationMenu()

        // Activate the application
        NSApp.activate(ignoringOtherApps: true)
        logger.logPlatformCall("NSApplication.activate(ignoringOtherApps: true)")

        logger.logStateTransition("macOS application initialized successfully")
    }

    /// Set up the standard macOS application menu with Quit command
    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        // Application menu (first menu with app name)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        // Add "Quit AppName" menu item (Cmd+Q)
        let appName = ProcessInfo.processInfo.processName
        let quitMenuItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitMenuItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    public func run() throws {
        shouldQuit = false
        logger.logStateTransition("Event loop started: mode = run (blocking)")

        while !shouldQuit {
            // Block waiting for next event
            guard let nsEvent = NSApp.nextEvent(
                matching: .any,
                until: .distantFuture,
                inMode: .default,
                dequeue: true
            ) else {
                continue
            }

            // Send event to NSApp for standard processing
            NSApp.sendEvent(nsEvent)

            // Process any pending user events
            processUserEvents()
        }

        logger.logStateTransition("Event loop exited")
    }

    public func poll() throws -> Event? {
        // Loop until we find a translatable event or run out of events
        while true {
            // Check for pending NSEvents (non-blocking)
            guard let nsEvent = NSApp.nextEvent(
                matching: .any,
                until: .distantPast,  // Non-blocking: return immediately
                inMode: .default,
                dequeue: true
            ) else {
                // No NSEvents available, check for window events first, then user events
                if let windowEvent = pollWindowEvent() {
                    return windowEvent
                }
                return pollUserEvent()
            }

            // Send event to NSApp for standard processing (window management, etc.)
            NSApp.sendEvent(nsEvent)

            // Try to translate to Lumina event if it's associated with a tracked window
            if let windowNumber = nsEvent.window?.windowNumber,
               let windowID = windowRegistry.windowID(for: windowNumber) {
                if let event = translateNSEvent(nsEvent, for: windowID) {
                    // Handle mouse focus: generate enter on first movement,
                    // respect exit but filter spurious ones
                    if case .pointer(let pointerEvent) = event {
                        switch pointerEvent {
                        case .moved(let id, _):
                            // Generate enter event on first movement in window
                            let wasInside = pointerInsideWindow[id] ?? false
                            if !wasInside {
                                pointerInsideWindow[id] = true
                                logger.logEvent("Pointer entered window: id = \(id)")
                                return .pointer(.entered(id))
                            }
                        case .entered(_):
                            // Ignore enter events - generate from move instead
                            continue
                        case .left(let id):
                            // Respect exit events, but only if we were inside
                            if pointerInsideWindow[id] == true {
                                pointerInsideWindow[id] = false
                                logger.logEvent("Pointer left window: id = \(id)")
                            } else {
                                // Skip spurious exit
                                continue
                            }
                        default:
                            break
                        }
                    }
                    return event
                }
            }

            // Event processed but not translatable (e.g., menu events, system events)
            // Continue looping to check for the next event
        }
    }

    /// Poll for a single window event from the queue.
    private func pollWindowEvent() -> Event? {
        let pendingEvents = windowEventQueue.removeAll()
        guard let windowEvent = pendingEvents.first else {
            return nil
        }

        // Re-queue remaining events
        for event in pendingEvents.dropFirst() {
            windowEventQueue.append(event)
        }

        return .window(windowEvent)
    }

    /// Poll for a single user event from the queue.
    private func pollUserEvent() -> Event? {
        let pendingEvents = userEventQueue.removeAll()
        guard let userEvent = pendingEvents.first else {
            return nil
        }

        // Re-queue remaining events
        for event in pendingEvents.dropFirst() {
            userEventQueue.append(event)
        }

        return .user(userEvent)
    }

    public func wait() throws {
        // Use CFRunLoop for low-power wait
        // This will block until an event arrives, then return without processing it
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, .infinity, true)

        // After waking up, process user events
        processUserEvents()
    }

    public func pumpEvents(mode: ControlFlowMode) -> Event? {
        logger.logDebug("pumpEvents: mode = \(mode)")

        // Determine timeout based on control flow mode
        let timeout: Date 
        switch mode {
        case .wait:
            logger.logStateTransition("Event loop mode: wait (blocking)")
            timeout = Date.distantFuture
        case .poll:
            logger.logStateTransition("Event loop mode: poll (non-blocking)")
            timeout = Date.distantPast
        case .waitUntil(let deadline):
            logger.logStateTransition("Event loop mode: waitUntil (deadline = \(deadline.date))")
            timeout = deadline.internalDate
        }

        // Check for redraw requests first (priority handling)
        if let windowID = redrawRequests.first {
            redrawRequests.remove(windowID)
            return .redraw(.requested(windowID, dirtyRect: nil))
        }

        // Process platform events with timeout
        while let nsEvent = NSApp.nextEvent(
            matching: .any,
            until: timeout,
            inMode: .default,
            dequeue: true
        ) {
            NSApp.sendEvent(nsEvent)

            // Try to translate to Lumina event
            if let windowNumber = nsEvent.window?.windowNumber,
               let windowID = windowRegistry.windowID(for: windowNumber) {
                if let event = translateNSEvent(nsEvent, for: windowID) {
                    // Handle mouse focus: generate enter on first movement,
                    // respect exit but filter spurious ones
                    if case .pointer(let pointerEvent) = event {
                        switch pointerEvent {
                        case .moved(let id, _):
                            // Generate enter event on first movement in window
                            let wasInside = pointerInsideWindow[id] ?? false
                            if !wasInside {
                                pointerInsideWindow[id] = true
                                logger.logEvent("Pointer entered window: id = \(id)")
                                return .pointer(.entered(id))
                            }
                        case .entered(_):
                            // Ignore enter events - generate from move instead
                            continue
                        case .left(let id):
                            // Respect exit events, but only if we were inside
                            if pointerInsideWindow[id] == true {
                                pointerInsideWindow[id] = false
                                logger.logEvent("Pointer left window: id = \(id)")
                            } else {
                                // Skip spurious exit
                                continue
                            }
                        default:
                            break
                        }
                    }
                    return event
                }
            }

            // In poll mode, don't block waiting for more events
            if case .poll = mode {
                break
            }
        }

        // Check for window events
        if let windowEvent = pollWindowEvent() {
            return windowEvent
        }

        // Check for user events
        return pollUserEvent()
    }

    /// Mark a window as needing redraw
    internal func markWindowNeedsRedraw(_ windowID: WindowID) {
        redrawRequests.insert(windowID)

        // Wake up the event loop
        let dummyEvent = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        )
        if let event = dummyEvent {
            NSApp.postEvent(event, atStart: false)
        }
    }

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

    public func postUserEvent(_ event: UserEvent) {
        // Thread-safe enqueue
        userEventQueue.append(event)

        // Wake up the event loop by posting a dummy NSEvent
        // This ensures wait() wakes up when a user event is posted
        // Post to MainActor since NSApp.postEvent requires main thread
        Task { @MainActor in
            let dummyEvent = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            )

            if let event = dummyEvent {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    public func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> MacWindow {
        logger.logEvent("Creating window: title = '\(title)', size = \(size), resizable = \(resizable)")

        // Capture windowEventQueue for posting close events
        let eventQueue = windowEventQueue
        let windowLogger = logger

        // Create the window using MacWindow
        let macWindow = try MacWindow.create(
            title: title,
            size: size,
            resizable: resizable,
            monitor: monitor,
            closeCallback: { [onWindowClosed] windowID in
                windowLogger.logEvent("Window closed: id = \(windowID)")

                // Post a window closed event so custom event loops can detect it
                eventQueue.append(.closed(windowID))

                // Wake up the event loop
                let dummyEvent = NSEvent.otherEvent(
                    with: .applicationDefined,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0,
                    context: nil,
                    subtype: 0,
                    data1: 0,
                    data2: 0
                )
                if let event = dummyEvent {
                    NSApp.postEvent(event, atStart: false)
                }

                // Trigger the application's close callback
                onWindowClosed?(windowID)
            }
        )

        // Register the window
        windowRegistry.register(macWindow.windowNumber, id: macWindow.id)
        logger.logEvent("Window created successfully: id = \(macWindow.id), windowNumber = \(macWindow.windowNumber)")

        return macWindow
    }

    func setWindowCloseCallback(_ callback: @escaping WindowCloseCallback) {
        onWindowClosed = callback
    }

    public func quit() {
        logger.logStateTransition("Application quit requested")

        // Request application termination
        // This will cause the event loop to exit
        NSApp.stop(nil)
        logger.logPlatformCall("NSApplication.stop(nil)")

        // Post a dummy event to wake up the event loop immediately
        let dummyEvent = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        )

        if let event = dummyEvent {
            NSApp.postEvent(event, atStart: false)
        }
    }

    // MARK: - Private Helpers

    /// Process all pending user events from the thread-safe queue.
    ///
    /// - Returns: true if any user events were processed
    @discardableResult
    private func processUserEvents() -> Bool {
        let pendingEvents = userEventQueue.removeAll()

        guard !pendingEvents.isEmpty else {
            return false
        }

        for userEvent in pendingEvents {
            // In a full implementation, this would dispatch to registered handlers
            // For now, we just ensure the event is dequeued
            // The public API layer will handle event callbacks
            _ = userEvent
        }

        return true
    }
}

#endif
