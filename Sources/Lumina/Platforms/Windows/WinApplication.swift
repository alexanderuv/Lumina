#if os(Windows)
import WinSDK
import Foundation

/// Windows implementation of PlatformApp using Win32 API.
///
/// This implementation wraps the Windows message pump and provides
/// Lumina's cross-platform event loop interface. It handles WM_* message
/// translation, user event queuing, and low-power wait modes.
///
/// Platform-specific initialization:
/// - Sets DPI awareness (Per-Monitor V2 preferred, falls back to V1)
/// - Initializes COM for Windows API usage

/// The DPI awareness level of the application.
public enum DpiAwarenessLevel: Sendable {
    /// DPI awareness is not set or invalid
    case unaware
    /// Application is system DPI aware (scales to primary monitor)
    case systemAware
    /// Application is per-monitor DPI aware (V1)
    case perMonitorAware
    /// Application is per-monitor DPI aware V2 (Windows 10 1703+)
    case perMonitorAwareV2
    /// DPI awareness could not be determined
    case unknown
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

/// Thread-safe window event queue (removed - using GlobalEventQueue in WinWindow.swift)
/// This class is no longer needed as we removed the duplicate WindowEventQueue

// Custom message ID for user events (WM_USER + 1)
private let WM_LUMINA_USER_EVENT: UINT = UINT(WM_USER + 1)

/// Windows implementation of LuminaApp.
///
/// **Do not instantiate this type directly.** Use `LuminaApp.create()` instead.
///
/// This type is public only because Swift requires it for protocol extensions.
/// It should be treated as an implementation detail.
@MainActor
struct WinApplication: LuminaApp {
    private var shouldQuit: Bool = false
    private let userEventQueue = UserEventQueue()
    // Note: Window tracking is handled by WinWindowRegistry in WinWindow.swift
    private var onWindowClosed: WindowCloseCallback?

    /// The main thread ID - captured at init time for thread-safe postUserEvent
    private let mainThreadId: DWORD

    /// The detected DPI awareness level of the application
    private(set) var dpiAwarenessLevel: DpiAwarenessLevel = .unknown

    /// Whether the application should quit when the last window is closed.
    var exitOnLastWindowClosed: Bool = true

    init() throws {
        // Capture the main thread ID for use in postUserEvent
        self.mainThreadId = GetCurrentThreadId()
        // Set DPI awareness for proper scaling
        // Try Per-Monitor V2 first (Windows 10 1703+), which automatically scales non-client areas
        // If that fails, fall back to Per-Monitor V1
        if SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) {
            // Successfully set to Per-Monitor V2
            self.dpiAwarenessLevel = .perMonitorAwareV2
        } else {
            // Fallback to V1 for older Windows versions
            let result = SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)
            if result == S_OK {
                self.dpiAwarenessLevel = .perMonitorAware
            } else {
                // Failed to set DPI awareness - query what we actually have
                self.dpiAwarenessLevel = Self.queryDpiAwarenessLevel()
            }
        }
    }

    public mutating func run() throws {
        shouldQuit = false

        // Windows message pump - blocking until quit
        var msg = MSG()
        while true {
            let hasMessage = GetMessageW(&msg, nil, 0, 0)
            if !hasMessage || msg.message == UINT(WM_QUIT) {
                break
            }

            TranslateMessage(&msg)
            DispatchMessageW(&msg)

            // Process user events if we received our custom message
            if msg.message == WM_LUMINA_USER_EVENT {
                processUserEvents()
            }
        }
    }

    mutating func poll() throws -> Event? {
        // First, check if we have any queued events from WndProc
        if let event = GlobalEventQueue.shared.removeFirst() {
            return event
        }

        // Process Windows messages until we get an event or run out of messages
        while true {
            // Non-blocking message pump
            var msg = MSG()

            guard PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) else {
                // No messages available, check queue one more time
                return GlobalEventQueue.shared.removeFirst()
            }

            TranslateMessage(&msg)
            DispatchMessageW(&msg)

            // Check for user events
            if msg.message == WM_LUMINA_USER_EVENT {
                // Check if user event is in queue, otherwise return nil
                if let userEvent = pollUserEvent() {
                    return userEvent
                }
            }

            // After processing messages, check if WndProc queued any events
            if let event = GlobalEventQueue.shared.removeFirst() {
                return event
            }

            // Continue looping to process more messages
        }
    }

    /// Poll for a single user event from the queue.
    private mutating func pollUserEvent() -> Event? {
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

    public mutating func wait() throws {
        // Low-power wait for next message
        WaitMessage()

        // After waking, process one message
        var msg = MSG()
        if PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)

            if msg.message == WM_LUMINA_USER_EVENT {
                processUserEvents()
            }
        }
    }

    public func postUserEvent(_ event: UserEvent) {
        // Add event to queue
        userEventQueue.append(event)

        // Wake up the message loop by posting a custom message to the MAIN thread
        // Use the captured mainThreadId, not GetCurrentThreadId() which returns the calling thread
        PostThreadMessageW(mainThreadId, WM_LUMINA_USER_EVENT, 0, 0)
    }

    mutating func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> LuminaWindow {
        // Capture values for the close callback
        let threadId = mainThreadId
        let shouldExitOnLastWindow = exitOnLastWindowClosed

        // Create the window using WinWindow
        let winWindow = try WinWindow.create(
            title: title,
            size: size,
            resizable: resizable,
            monitor: monitor,
            closeCallback: { [onWindowClosed] windowID in
                // Note: WinWindowRegistry.unregister() is already called by WndProc on WM_DESTROY
                // So we don't need to unregister here

                // Post a window closed event for custom event loops
                GlobalEventQueue.shared.append(.window(.closed(windowID)))

                // Wake up the event loop by posting a user event
                PostThreadMessageW(threadId, WM_LUMINA_USER_EVENT, 0, 0)

                // Trigger the application's close callback
                onWindowClosed?(windowID)

                // Check if we should quit (after the callbacks)
                // WinWindowRegistry already tracks window count
                if shouldExitOnLastWindow && WinWindowRegistry.shared.windowCount == 0 {
                    PostQuitMessage(0)
                }
            }
        )

        // Note: Window is registered in WinWindowRegistry by WinWindow.create()
        // No need for duplicate tracking here

        return winWindow as LuminaWindow
    }

    mutating func setWindowCloseCallback(_ callback: @escaping WindowCloseCallback) {
        onWindowClosed = callback
    }

    mutating func quit() {
        // Post quit message to terminate the message loop
        PostQuitMessage(0)
        shouldQuit = true
    }

    // MARK: - Private Helpers

    private mutating func processUserEvents() {
        let _ = userEventQueue.removeAll()
        // In Milestone 0, we don't have a callback mechanism yet
        // User events are queued but need to be retrieved through
        // a future API (event handlers/callbacks will be added later)
        // For now, they're just processed and discarded
    }

    /// Queries the current DPI awareness level from Windows
    private static func queryDpiAwarenessLevel() -> DpiAwarenessLevel {
        // Get the DPI awareness context for the current thread
        guard let context = GetThreadDpiAwarenessContext() else {
            return .unknown
        }

        // Extract the DPI_AWARENESS value from the context
        let awareness = GetAwarenessFromDpiAwarenessContext(context)

        // Map the Windows constant to our enum
        // Note: DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 maps to DPI_AWARENESS_PER_MONITOR_AWARE (2)
        // We need to check the actual context value to distinguish V1 from V2
        if AreDpiAwarenessContextsEqual(context, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) {
            return .perMonitorAwareV2
        } else if AreDpiAwarenessContextsEqual(context, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE) {
            return .perMonitorAware
        } else {
            switch awareness {
            case DPI_AWARENESS_UNAWARE:
                return .unaware
            case DPI_AWARENESS_SYSTEM_AWARE:
                return .systemAware
            case DPI_AWARENESS_PER_MONITOR_AWARE:
                // This shouldn't happen if the context checks above work
                return .perMonitorAware
            default:
                return .unknown
            }
        }
    }
}

// MARK: - Sendable Conformance

extension WinApplication: @unchecked Sendable {}

#endif
