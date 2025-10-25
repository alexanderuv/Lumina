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

/// Thread-safe unified event queue (FIFO)
internal final class EventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Event] = []

    func append(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    func appendAll(_ newEvents: [Event]) {
        lock.lock()
        defer { lock.unlock() }
        events.append(contentsOf: newEvents)
    }

    func removeFirst() -> Event? {
        lock.lock()
        defer { lock.unlock() }
        guard !events.isEmpty else {
            return nil
        }
        return events.removeFirst()
    }

    func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return events.isEmpty
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
    private let eventQueue = EventQueue()
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
        self.logger = LuminaLogger.makeLogger(label: "lumina.macos")
        logger.info("Initializing macOS application")

        // Ensure NSApplication is initialized
        _ = NSApplication.shared
        logger.debug("NSApplication.shared")

        // Create and set app delegate
        let delegate = MacAppDelegate()
        self.appDelegate = delegate
        if NSApp.delegate == nil {
            NSApp.delegate = delegate
        }

        // Set activation policy to regular app (shows in Dock)
        NSApp.setActivationPolicy(.regular)
        logger.debug("NSApplication.setActivationPolicy(.regular)")

        // Create a standard application menu with Quit support
        setupApplicationMenu()

        // Activate the application
        NSApp.activate(ignoringOtherApps: true)
        logger.debug("NSApplication.activate(ignoringOtherApps: true)")

        logger.info("macOS application initialized successfully")
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
        logger.info("Event loop started: mode = run (blocking)")

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
        }

        logger.info("Event loop exited")
    }

    public func poll() throws -> Event? {
        // Check unified event queue first (FIFO)
        if let event = eventQueue.removeFirst() {
            return event
        }

        // No queued events, poll for new OS events
        while true {
            // Check for pending NSEvents (non-blocking)
            guard let nsEvent = NSApp.nextEvent(
                matching: .any,
                until: .distantPast,  // Non-blocking: return immediately
                inMode: .default,
                dequeue: true
            ) else {
                // No OS events available
                return nil
            }

            // Send event to NSApp for standard processing (window management, etc.)
            NSApp.sendEvent(nsEvent)

            // Try to translate to Lumina events if associated with a tracked window
            if let windowNumber = nsEvent.window?.windowNumber,
               let windowID = windowRegistry.windowID(for: windowNumber) {
                let events = translateNSEvent(nsEvent, for: windowID)
                guard !events.isEmpty else {
                    continue
                }

                // Handle special pointer tracking logic
                var eventsToQueue: [Event] = []
                for event in events {
                    if case .pointer(let pointerEvent) = event {
                        switch pointerEvent {
                        case .moved(let id, let position):
                            // Generate enter event on first movement in window
                            let wasInside = pointerInsideWindow[id] ?? false
                            if !wasInside {
                                pointerInsideWindow[id] = true
                                logger.debug("Pointer entered window: id = \(id)")
                                eventsToQueue.append(.pointer(.entered(id, position: position)))
                            }
                            eventsToQueue.append(event)
                        case .entered(_, _):
                            // Ignore enter events - we generate them from move
                            continue
                        case .left(let id, _):
                            // Respect exit events, but only if we were inside
                            if pointerInsideWindow[id] == true {
                                pointerInsideWindow[id] = false
                                logger.debug("Pointer left window: id = \(id)")
                                eventsToQueue.append(event)
                            }
                            // Skip spurious exits
                        default:
                            eventsToQueue.append(event)
                        }
                    } else {
                        eventsToQueue.append(event)
                    }
                }

                // Queue all events and return the first one
                guard !eventsToQueue.isEmpty else {
                    continue
                }

                eventQueue.appendAll(eventsToQueue)
                return eventQueue.removeFirst()
            }

            // Event processed but not translatable (e.g., menu events, system events)
            // Continue looping to check for the next event
        }
    }

    public func wait() throws {
        // Use CFRunLoop for low-power wait
        // This will block until an event arrives, then return without processing it
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, .infinity, true)
    }

    public func pumpEvents(mode: ControlFlowMode) -> Event? {
        logger.debug("pumpEvents: mode = \(mode)")

        // Check unified event queue first (FIFO)
        if let event = eventQueue.removeFirst() {
            return event
        }

        // Check for redraw requests (priority handling after queued events)
        if let windowID = redrawRequests.first {
            redrawRequests.remove(windowID)
            return .redraw(.requested(windowID, dirtyRect: nil))
        }

        // Determine timeout based on control flow mode
        let timeout: Date = switch mode {
        case .wait:
            .distantFuture
        case .poll:
            .distantPast
        case .waitUntil(let deadline):
            deadline.internalDate
        }

        // Process platform events with timeout
        while let nsEvent = NSApp.nextEvent(
            matching: .any,
            until: timeout,
            inMode: .default,
            dequeue: true
        ) {
            NSApp.sendEvent(nsEvent)

            // Try to translate to Lumina events
            if let windowNumber = nsEvent.window?.windowNumber,
               let windowID = windowRegistry.windowID(for: windowNumber) {
                let events = translateNSEvent(nsEvent, for: windowID)
                guard !events.isEmpty else {
                    continue
                }

                // Handle special pointer tracking logic
                var eventsToQueue: [Event] = []
                for event in events {
                    if case .pointer(let pointerEvent) = event {
                        switch pointerEvent {
                        case .moved(let id, let position):
                            // Generate enter event on first movement in window
                            let wasInside = pointerInsideWindow[id] ?? false
                            if !wasInside {
                                pointerInsideWindow[id] = true
                                logger.debug("Pointer entered window: id = \(id)")
                                eventsToQueue.append(.pointer(.entered(id, position: position)))
                            }
                            eventsToQueue.append(event)
                        case .entered(_, _):
                            // Ignore enter events - we generate them from move
                            continue
                        case .left(let id, _):
                            // Respect exit events, but only if we were inside
                            if pointerInsideWindow[id] == true {
                                pointerInsideWindow[id] = false
                                logger.debug("Pointer left window: id = \(id)")
                                eventsToQueue.append(event)
                            }
                            // Skip spurious exits
                        default:
                            eventsToQueue.append(event)
                        }
                    } else {
                        eventsToQueue.append(event)
                    }
                }

                // Queue all events and return the first one
                guard !eventsToQueue.isEmpty else {
                    continue
                }

                eventQueue.appendAll(eventsToQueue)
                return eventQueue.removeFirst()
            }

            // In poll mode, don't block waiting for more events
            if case .poll = mode {
                break
            }
        }

        // No events available
        return nil
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
        let logger = LuminaLogger(label: "lumina.macos", level: .debug)
        logger.debug("Monitor capabilities: dynamic refresh rate = true (ProMotion), fractional scaling = true (Retina)")
        return MonitorCapabilities(
            supportsDynamicRefreshRate: true,  // ProMotion on supported hardware
            supportsFractionalScaling: true     // Retina scaling modes
        )
    }

    public static func clipboardCapabilities() -> ClipboardCapabilities {
        // macOS supports text clipboard via NSPasteboard
        // Images and HTML support is future work
        let logger = LuminaLogger(label: "lumina.macos", level: .debug)
        logger.debug("Clipboard capabilities: text = true, images = false, HTML = false")
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,
            supportsHTML: false
        )
    }

    public func postUserEvent(_ event: UserEvent) {
        // Thread-safe enqueue to unified event queue
        eventQueue.append(.user(event))

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
        logger.info("Creating window: title = '\(title)', size = \(size), resizable = \(resizable)")

        // Capture unified eventQueue for posting window events
        let capturedEventQueue = eventQueue
        let windowLogger = logger

        // Create the window using MacWindow
        let macWindow = try MacWindow.create(
            title: title,
            size: size,
            resizable: resizable,
            monitor: monitor,
            closeCallback: { [onWindowClosed] windowID in
                windowLogger.info("Window closed: id = \(windowID)")

                // Post a window closed event to unified event queue
                capturedEventQueue.append(.window(.closed(windowID)))

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
            },
            eventQueue: capturedEventQueue
        )

        // Register the window
        windowRegistry.register(macWindow.windowNumber, id: macWindow.id)
        logger.info("Window created successfully: id = \(macWindow.id), windowNumber = \(macWindow.windowNumber)")

        return macWindow
    }

    func setWindowCloseCallback(_ callback: @escaping WindowCloseCallback) {
        onWindowClosed = callback
    }

    public func quit() {
        logger.info("Application quit requested")

        // Request application termination
        // This will cause the event loop to exit
        NSApp.stop(nil)
        logger.debug("NSApplication.stop(nil)")

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
}

#endif
