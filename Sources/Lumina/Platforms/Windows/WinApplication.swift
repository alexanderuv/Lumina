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

// Custom message ID for user events (WM_USER + 1)
private let WM_LUMINA_USER_EVENT: UINT = UINT(WM_USER + 1)

/// Windows implementation of LuminaApp.
///
/// **Do not instantiate this type directly.** Use `LuminaApp.create()` instead.
///
/// This type is public only because Swift requires it for protocol extensions.
/// It should be treated as an implementation detail.
@MainActor
public final class WinApplication: LuminaApp {
    public typealias Window = WinWindow

    private var shouldQuit: Bool = false
    // Note: Window tracking is handled by WinWindowRegistry in WinWindow.swift
    private var onWindowClosed: WindowCloseCallback?

    /// FIFO event queue for all events (system + user)
    /// Accessed by WndProc via WinPlatform.shared.app
    internal var eventQueue: [Event] = []

    /// The main thread ID - captured at init time for thread-safe postUserEvent
    private let mainThreadId: DWORD

    /// The detected DPI awareness level of the application
    private(set) var dpiAwarenessLevel: DpiAwarenessLevel = .unknown

    /// Whether the application should quit when the last window is closed.
    public var exitOnLastWindowClosed: Bool = true

    init(platform: WinPlatform) throws {
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
        // Register self with platform for WndProc access (must be after all properties initialized)
        platform.app = self
    }

    public func run() throws {
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
        }
    }

    public func poll() throws -> Event? {
        // Check event queue first for FIFO ordering
        if let event = pollFromQueue() {
            return event
        }

        // Process all available Windows messages until we get an event or run out
        // Loop here to give Tasks (scheduled from WndProc) a chance to execute
        while true {
            var msg = MSG()

            guard PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) else {
                // No more messages, check queue one final time
                return pollFromQueue()
            }

            TranslateMessage(&msg)
            DispatchMessageW(&msg)

            // Check if WndProc queued any events via Task
            if let event = pollFromQueue() {
                return event
            }

            // Continue processing messages
        }
    }

    private func pollFromQueue() -> Event? {
        guard !eventQueue.isEmpty else { return nil }
        return eventQueue.removeFirst()
    }

    public func wait() throws {
        if !eventQueue.isEmpty {
            return
        }

        // Low-power wait for next message
        WaitMessage()
    }

    public func postUserEvent(_ event: UserEvent) {
        // Add event to app's event queue for FIFO ordering
        eventQueue.append(Event.user(event))

        // Wake up the message loop if it's waiting
        PostThreadMessageW(mainThreadId, WM_LUMINA_USER_EVENT, 0, 0)
    }

    public func createWindow(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor?
    ) throws -> WinWindow {
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

                // Post a window closed event to app's event queue
                self.eventQueue.append(Event.window(.closed(windowID)))

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

        return winWindow
    }

    func setWindowCloseCallback(_ callback: @escaping WindowCloseCallback) {
        onWindowClosed = callback
    }

    public func quit() {
        // Post quit message to terminate the message loop
        PostQuitMessage(0)
        shouldQuit = true
    }

    public func pumpEvents(mode: ControlFlowMode) -> Event? {
        // Check if we have any queued events
        if let event = pollFromQueue() {
            return event
        }

        switch mode {
        case .wait:
            // Block until an event arrives
            WaitMessage()
            // Process one message
            var msg = MSG()
            if PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }
            // Check queue after processing
            return pollFromQueue()

        case .poll:
            // Non-blocking poll
            return try? poll()

        case .waitUntil(let deadline):
            // Wait with timeout
            let now = Date()
            let timeoutSeconds = deadline.internalDate.timeIntervalSince(now)
            let timeoutMs = max(0, Int(timeoutSeconds * 1000))
            if timeoutMs > 0 {
                _ = MsgWaitForMultipleObjects(0, nil, false, DWORD(timeoutMs), UINT(QS_ALLINPUT))
            }
            // Process available messages
            var msg = MSG()
            if PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }
            // Check queue after processing
            return pollFromQueue()
        }
    }

    // MARK: - Private Helpers
    // (No helper methods needed - all events use unified GlobalEventQueue)

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
// @MainActor types automatically conform to Sendable via actor isolation
// No need for explicit @unchecked Sendable conformance

#endif
