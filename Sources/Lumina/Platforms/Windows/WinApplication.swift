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

// Custom message ID for user events (WM_USER + 1)
private let WM_LUMINA_USER_EVENT: UINT = UINT(WM_USER + 1)

@MainActor
public struct WinApplication: PlatformApp {
    private var shouldQuit: Bool = false
    private let userEventQueue = UserEventQueue()

    /// The detected DPI awareness level of the application
    public private(set) var dpiAwarenessLevel: DpiAwarenessLevel = .unknown

    public init() throws {
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

    public mutating func poll() throws -> Bool {
        // Non-blocking message pump
        var msg = MSG()
        var processedAny = false

        while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
            processedAny = true

            // Process user events if we received our custom message
            if msg.message == WM_LUMINA_USER_EVENT {
                processUserEvents()
            }
        }

        return processedAny
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

        // Wake up the message loop by posting a custom message
        // We post to the thread message queue (HWND_BROADCAST ensures delivery)
        PostThreadMessageW(GetCurrentThreadId(), WM_LUMINA_USER_EVENT, 0, 0)
    }

    public func quit() {
        // Post quit message to terminate the message loop
        PostQuitMessage(0)
        var mutableSelf = self
        mutableSelf.shouldQuit = true
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
