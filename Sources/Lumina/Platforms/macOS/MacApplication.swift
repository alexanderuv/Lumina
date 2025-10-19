#if os(macOS)
import AppKit
import Foundation


/// macOS implementation of PlatformApp using AppKit.
///
/// This implementation wraps NSApplication's event loop and provides
/// Lumina's cross-platform event loop interface. It handles NSEvent
/// translation, user event queuing, and low-power wait modes.
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

@MainActor
internal struct MacApplication: PlatformApp {
    private var shouldQuit: Bool = false
    private let userEventQueue = UserEventQueue()

    internal init() throws {
        // Ensure NSApplication is initialized
        _ = NSApplication.shared

        // Set activation policy to regular app (shows in Dock)
        NSApp.setActivationPolicy(.regular)

        // Create a standard application menu with Quit support
        setupApplicationMenu()

        // Activate the application
        NSApp.activate(ignoringOtherApps: true)
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

    mutating func run() throws {
        shouldQuit = false

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
    }

    mutating func poll() throws -> Bool {
        var processedAny = false

        // Process all available NSEvents (non-blocking)
        while let nsEvent = NSApp.nextEvent(
            matching: .any,
            until: .distantPast,  // Non-blocking: return immediately
            inMode: .default,
            dequeue: true
        ) {
            NSApp.sendEvent(nsEvent)
            processedAny = true
        }

        // Process any pending user events
        if processUserEvents() {
            processedAny = true
        }

        return processedAny
    }

    mutating func wait() throws {
        // Use CFRunLoop for low-power wait
        // This will block until an event arrives, then return without processing it
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, .infinity, true)

        // After waking up, process user events
        processUserEvents()
    }

    nonisolated func postUserEvent(_ event: UserEvent) {
        // Thread-safe enqueue
        userEventQueue.append(event)

        // Wake up the event loop by posting a dummy NSEvent
        // This ensures wait() wakes up when a user event is posted
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
            // NSApp.postEvent is main-actor isolated, but it's safe to call from any thread
            MainActor.assumeIsolated {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    func quit() {
        // Request application termination
        // This will cause the event loop to exit
        NSApp.stop(nil)

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
    private mutating func processUserEvents() -> Bool {
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

// MARK: - Sendable Conformance

// MacApplication is @MainActor isolated, so it's safe to conform to Sendable
// The userEventLock protects the shared mutable state (userEventQueue)
extension MacApplication: @unchecked Sendable {}

#endif
