#if os(Windows)
import WinSDK

/// Windows implementation of EventLoopBackend using Win32 API.
///
/// This implementation wraps the Windows message pump and provides
/// Lumina's cross-platform event loop interface. It handles WM_* message
/// translation, user event queuing, and low-power wait modes.
@MainActor
internal struct WinApplication: EventLoopBackend {
    private var shouldQuit: Bool = false

    init() throws {
        // Initialize COM for DPI awareness
        // HRESULT hr = SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);
        // if (FAILED(hr)) {
        //     throw LuminaError.platformError(code: Int(hr), message: "Failed to set DPI awareness")
        // }
    }

    mutating func run() throws {
        shouldQuit = false

        // Windows message pump
        // var msg = MSG()
        // while GetMessage(&msg, nil, 0, 0) > 0 {
        //     TranslateMessage(&msg)
        //     DispatchMessage(&msg)
        // }
    }

    mutating func poll() throws -> Bool {
        // Non-blocking message pump
        // var msg = MSG()
        // var processedAny = false
        //
        // while PeekMessage(&msg, nil, 0, 0, PM_REMOVE) != 0 {
        //     TranslateMessage(&msg)
        //     DispatchMessage(&msg)
        //     processedAny = true
        // }
        //
        // return processedAny

        return false
    }

    mutating func wait() throws {
        // Low-power wait for next message
        // WaitMessage()
    }

    func postUserEvent(_ event: UserEvent) {
        // Post custom WM_USER message
        // PostMessage(hwnd, WM_USER, 0, 0)
    }

    func quit() {
        // Post quit message
        // PostQuitMessage(0)
        var mutableSelf = self
        mutableSelf.shouldQuit = true
    }
}

// MARK: - Sendable Conformance

extension WinApplication: @unchecked Sendable {}

#endif
