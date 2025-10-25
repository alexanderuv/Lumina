#if os(Windows)
import WinSDK
import Foundation

/// Global event queue for posting events from WndProc to the application.
///
/// Since WndProc is a static C callback, we need a global queue to communicate
/// events back to the application's poll() method.
internal final class GlobalEventQueue: @unchecked Sendable {
    static let shared = GlobalEventQueue()

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
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }
}

/// Global window registry for HWND -> WindowID mapping.
///
/// Windows requires a static C callback for WndProc, but we need to associate
/// each HWND with its Lumina WindowID. This registry provides that mapping.
internal final class WinWindowRegistry: @unchecked Sendable {
    static let shared = WinWindowRegistry()

    private let lock = NSLock()
    private var registry: [HWND: WindowID] = [:]
    private var constraints: [HWND: WindowConstraints] = [:]
    private var closeCallbacks: [HWND: WindowCloseCallback] = [:]

    struct WindowConstraints {
        var minSize: LogicalSize?
        var maxSize: LogicalSize?
    }

    func register(hwnd: HWND, windowID: WindowID, closeCallback: WindowCloseCallback?) {
        lock.lock()
        defer { lock.unlock() }
        registry[hwnd] = windowID
        constraints[hwnd] = WindowConstraints()
        if let callback = closeCallback {
            closeCallbacks[hwnd] = callback
        }
    }

    func unregister(hwnd: HWND) {
        lock.lock()
        defer { lock.unlock() }

        // Get the callback and windowID before removing
        let callback = closeCallbacks[hwnd]
        let windowID = registry[hwnd]

        registry.removeValue(forKey: hwnd)
        constraints.removeValue(forKey: hwnd)
        closeCallbacks.removeValue(forKey: hwnd)

        // Release the lock before invoking the callback
        lock.unlock()

        // Invoke the close callback if it exists
        // WndProc runs on the main thread, so we can use assumeIsolated
        if let callback = callback, let windowID = windowID {
            MainActor.assumeIsolated {
                callback(windowID)
            }
        }

        // Re-acquire the lock for the defer block
        lock.lock()
    }

    func windowID(for hwnd: HWND) -> WindowID? {
        lock.lock()
        defer { lock.unlock() }
        return registry[hwnd]
    }

    func setMinSize(_ size: LogicalSize?, for hwnd: HWND) {
        lock.lock()
        defer { lock.unlock() }
        constraints[hwnd]?.minSize = size
    }

    func setMaxSize(_ size: LogicalSize?, for hwnd: HWND) {
        lock.lock()
        defer { lock.unlock() }
        constraints[hwnd]?.maxSize = size
    }

    func getConstraints(for hwnd: HWND) -> WindowConstraints? {
        lock.lock()
        defer { lock.unlock() }
        return constraints[hwnd]
    }

    var windowCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return registry.count
    }
}

/// Windows window class name
private let LUMINA_WINDOW_CLASS = "LuminaWindow"

/// Register the window class (called once at startup)
private func registerWindowClass() -> Bool {
    // Keep the class name string in scope during registration
    return LUMINA_WINDOW_CLASS.withCString(encodedAs: UTF16.self) { classNamePtr in
        var wc = WNDCLASSEXW()
        wc.cbSize = DWORD(MemoryLayout<WNDCLASSEXW>.size)
        // CS_HREDRAW | CS_VREDRAW: Redraw entire window when resized horizontally or vertically
        // CS_DBLCLKS: Enable double-click events
        wc.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS)
        wc.lpfnWndProc = luminaWndProc
        wc.cbClsExtra = 0
        wc.cbWndExtra = 0
        wc.hInstance = GetModuleHandleW(nil)
        wc.hIcon = nil
        wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDC_ARROW = 32512
        wc.hbrBackground = nil
        wc.lpszMenuName = nil
        wc.lpszClassName = classNamePtr  // Pointer valid within this closure
        wc.hIconSm = nil

        return RegisterClassExW(&wc) != 0
    }
}

/// Static flag to ensure we only register the window class once
@MainActor
private var windowClassRegistered = false

/// Window procedure callback (static C function required by Win32)
private func luminaWndProc(
    _ hwnd: HWND?,
    _ uMsg: UINT,
    _ wParam: WPARAM,
    _ lParam: LPARAM
) -> LRESULT {
    guard let hwnd = hwnd else {
        return DefWindowProcW(nil, uMsg, wParam, lParam)
    }

    // Handle special messages
    switch uMsg {
    case UINT(WM_NCCREATE):
        // Enable non-client DPI scaling before DefWindowProc processes WM_NCCREATE
        // This must be called during WM_NCCREATE to take effect
        _ = EnableNonClientDpiScaling(hwnd)
        return DefWindowProcW(hwnd, uMsg, wParam, lParam)

    case UINT(WM_DESTROY):
        WinWindowRegistry.shared.unregister(hwnd: hwnd)
        // Note: Don't call PostQuitMessage here - let the close callback decide
        // whether to quit based on exitOnLastWindowClosed setting
        return 0

    case UINT(WM_CLOSE):
        // Don't destroy automatically - let Lumina handle it
        // Just translate to a close event
        DestroyWindow(hwnd)
        return 0

    case UINT(WM_GETMINMAXINFO):
        if let constraints = WinWindowRegistry.shared.getConstraints(for: hwnd) {
            // lParam contains pointer to MINMAXINFO structure
            let pMinMaxInfo = UnsafeMutablePointer<MINMAXINFO>(bitPattern: Int(truncatingIfNeeded: lParam))
            if let info = pMinMaxInfo {
                let dpi = GetDpiForWindow(hwnd)
                let scaleFactor = Float(dpi) / 96.0

                if let minSize = constraints.minSize {
                    let physical = minSize.toPhysical(scaleFactor: scaleFactor)
                    info.pointee.ptMinTrackSize.x = LONG(physical.width)
                    info.pointee.ptMinTrackSize.y = LONG(physical.height)
                }

                if let maxSize = constraints.maxSize {
                    let physical = maxSize.toPhysical(scaleFactor: scaleFactor)
                    info.pointee.ptMaxTrackSize.x = LONG(physical.width)
                    info.pointee.ptMaxTrackSize.y = LONG(physical.height)
                }
            }
        }
        return 0

    case UINT(WM_DPICHANGED):
        // Handle DPI change by using the suggested window rect from Windows
        // lParam contains a pointer to a RECT with the recommended size and position
        let suggestedRect = UnsafePointer<RECT>(bitPattern: Int(truncatingIfNeeded: lParam))
        if let rect = suggestedRect {
            // Use the suggested rect to reposition and resize the window
            // This ensures the window maintains its visual size and position on the new monitor
            SetWindowPos(
                hwnd,
                nil,
                rect.pointee.left,
                rect.pointee.top,
                rect.pointee.right - rect.pointee.left,
                rect.pointee.bottom - rect.pointee.top,
                UINT(SWP_NOZORDER | SWP_NOACTIVATE)
            )
        }

        // Still translate the event for application notification
        if let windowID = WinWindowRegistry.shared.windowID(for: hwnd) {
            if let event = translateWindowsMessage(msg: uMsg, wParam: wParam, lParam: lParam, for: windowID) {
                // Post event to global queue for poll() to retrieve
                GlobalEventQueue.shared.append(event)
            }
        }
        return 0

    case UINT(WM_ERASEBKGND):
        // Fill background with white using system color brush
        // wParam contains the HDC (handle to device context)
        // On 64-bit Windows, WPARAM is UInt64, HDC expects Int bitPattern
        let hdc = HDC(bitPattern: Int(truncatingIfNeeded: wParam))
        if hdc != nil {
            var rect = RECT()
            GetClientRect(hwnd, &rect)
            // Use GetSysColorBrush for a valid system brush handle
            if let brush = GetSysColorBrush(Int32(COLOR_WINDOW)) {
                _ = FillRect(hdc, &rect, brush)
            }
        }
        return 1  // Background erased

    case UINT(WM_PAINT):
        // Validate the entire client area to prevent infinite paint loops
        var ps = PAINTSTRUCT()
        if BeginPaint(hwnd, &ps) != nil {
            // No rendering API yet - just validate the client area
            EndPaint(hwnd, &ps)
        }
        return 0

    default:
        // Translate other events through WinInput
        if let windowID = WinWindowRegistry.shared.windowID(for: hwnd) {
            if let event = translateWindowsMessage(msg: uMsg, wParam: wParam, lParam: lParam, for: windowID) {
                // Post event to global queue for poll() to retrieve
                GlobalEventQueue.shared.append(event)
            }
        }
    }

    return DefWindowProcW(hwnd, uMsg, wParam, lParam)
}

/// Windows implementation of LuminaWindow using HWND.
///
/// This implementation wraps a Windows window handle (HWND) and provides
/// Lumina's cross-platform window interface. It handles DPI scaling,
/// window styles, and Win32 API calls.
@MainActor
internal struct WinWindow: LuminaWindow {
    let id: WindowID
    private var hwnd: HWND?

    /// Create a new Windows window.
    ///
    /// - Parameters:
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether the window can be resized by the user
    ///   - monitor: Optional monitor to create the window on (uses primary if nil)
    ///   - closeCallback: Optional callback to invoke when the window closes
    /// - Returns: Newly created WinWindow
    /// - Throws: LuminaError if window creation fails
    static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor? = nil,
        closeCallback: WindowCloseCallback? = nil
    ) throws -> WinWindow {
        // Register window class on first call
        if !windowClassRegistered {
            guard registerWindowClass() else {
                throw LuminaError.windowCreationFailed(reason: "Failed to register window class")
            }
            windowClassRegistered = true
        }

        // Configure window style
        let dwStyle: DWORD = resizable
            ? DWORD(WS_OVERLAPPEDWINDOW)
            : DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX)

        // Determine target monitor with fallback logic
        // Priority: specified monitor -> primary monitor -> system DPI fallback
        let targetMonitor: Monitor?
        if let monitor = monitor {
            targetMonitor = monitor
        } else {
            targetMonitor = try? Monitor.primary()
        }

        // Extract scale factor from monitor or fallback to system DPI
        let scaleFactor: Float
        if let monitor = targetMonitor {
            scaleFactor = monitor.scaleFactor
        } else {
            // Fallback to system DPI if monitor detection fails
            let systemDPI = GetDpiForSystem()
            scaleFactor = Float(systemDPI) / 96.0
        }

        // Determine window position based on whether we have a target monitor
        let defaultX: INT
        let defaultY: INT
        if let monitor = targetMonitor {
            // Position window on the target monitor (offset from monitor's top-left)
            // We need an explicit position here to ensure it appears on the correct monitor
            defaultX = INT(monitor.physicalPosition.x + 100)
            defaultY = INT(monitor.physicalPosition.y + 100)
        } else {
            // Use CW_USEDEFAULT to let Windows choose the default position
            defaultX = INT(CW_USEDEFAULT)
            defaultY = INT(CW_USEDEFAULT)
        }

        // Convert logical size to physical pixels
        let physical = size.toPhysical(scaleFactor: scaleFactor)

        // Calculate window rect including frame using DPI-aware API
        // This ensures window borders and title bar are correctly sized for the target DPI
        let targetDpi = UINT(scaleFactor)
        var rect = RECT(
            left: 0,
            top: 0,
            right: LONG(physical.width),
            bottom: LONG(physical.height)
        )
        // Use 0 for dwExStyle - no extended styles needed for basic window
        let dwExStyle = DWORD(0)
        AdjustWindowRectExForDpi(&rect, dwStyle, false, dwExStyle, targetDpi)

        let width = rect.right - rect.left
        let height = rect.bottom - rect.top

        // Create window with calculated size
        let hwnd = title.withCString(encodedAs: UTF16.self) { titlePtr in
            LUMINA_WINDOW_CLASS.withCString(encodedAs: UTF16.self) { classPtr in
                CreateWindowExW(
                    dwExStyle,                  // dwExStyle - no extended styles
                    classPtr,                   // Window class
                    titlePtr,                   // Window title
                    dwStyle,                    // Window style
                    defaultX,                   // x
                    defaultY,                   // y
                    width,                      // width
                    height,                     // height
                    nil,                        // parent
                    nil,                        // menu
                    GetModuleHandleW(nil),      // hInstance
                    nil                         // lpParam
                )
            }
        }

        guard let validHwnd = hwnd else {
            let error = GetLastError()
            throw LuminaError.windowCreationFailed(reason: "CreateWindowExW failed with error \(error)")
        }

        // ALWAYS refresh the window frame at high DPI to fix title bar positioning
        // Even if DPI matches, the initial frame calculation may be incorrect
        let actualDPI = GetDpiForWindow(validHwnd)
        let actualScaleFactor = Float(actualDPI) / 96.0
        let actualPhysical = size.toPhysical(scaleFactor: actualScaleFactor)

        var adjustedRect = RECT(
            left: 0,
            top: 0,
            right: LONG(actualPhysical.width),
            bottom: LONG(actualPhysical.height)
        )
        AdjustWindowRectExForDpi(&adjustedRect, dwStyle, false, 0, actualDPI)

        // Always set the size to ensure proper frame metrics
        SetWindowPos(
            validHwnd,
            nil,
            0, 0,
            adjustedRect.right - adjustedRect.left,
            adjustedRect.bottom - adjustedRect.top,
            UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)
        )

        // Force frame recalculation to fix title bar positioning at high DPI
        SetWindowPos(
            validHwnd,
            nil,
            0, 0, 0, 0,
            UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)
        )

        // Invalidate and immediately redraw the non-client area (title bar)
        RedrawWindow(
            validHwnd,
            nil,
            nil,
            UINT(RDW_FRAME | RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN)
        )

        // Update the window to process all pending paint messages
        UpdateWindow(validHwnd)

        let windowID = WindowID()
        WinWindowRegistry.shared.register(hwnd: validHwnd, windowID: windowID, closeCallback: closeCallback)

        return WinWindow(id: windowID, hwnd: validHwnd)
    }

    mutating func show() {
        guard let hwnd = hwnd else { return }
        ShowWindow(hwnd, SW_SHOW)
        UpdateWindow(hwnd)

        // Force another frame update after showing to ensure title bar is rendered correctly
        // This is especially needed at high DPI (200%+)
        SetWindowPos(
            hwnd,
            nil,
            0, 0, 0, 0,
            UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)
        )

        // Invalidate non-client area one more time after window is visible
        RedrawWindow(
            hwnd,
            nil,
            nil,
            UINT(RDW_FRAME | RDW_INVALIDATE | RDW_UPDATENOW)
        )
    }

    mutating func hide() {
        guard let hwnd = hwnd else { return }
        ShowWindow(hwnd, SW_HIDE)
    }

    consuming func close() {
        guard let hwnd = hwnd else { return }
        DestroyWindow(hwnd)
    }

    mutating func setTitle(_ title: borrowing String) {
        guard let hwnd = hwnd else { return }
        _ = title.withCString(encodedAs: UTF16.self) { titlePtr in
            SetWindowTextW(hwnd, titlePtr)
        }
    }

    borrowing func size() -> LogicalSize {
        guard let hwnd = hwnd else { return LogicalSize(width: 0, height: 0) }

        var rect = RECT()
        GetClientRect(hwnd, &rect)
        let scaleFactor = scaleFactor()
        return PhysicalSize(
            width: Int(rect.right - rect.left),
            height: Int(rect.bottom - rect.top)
        ).toLogical(scaleFactor: scaleFactor)
    }

    mutating func resize(_ size: borrowing LogicalSize) {
        guard let hwnd = hwnd else { return }

        let currentScaleFactor = scaleFactor()
        let physical = size.toPhysical(scaleFactor: currentScaleFactor)

        // Get current window style
        let dwStyle = DWORD(GetWindowLongPtrW(hwnd, GWL_STYLE))
        let dwExStyle = DWORD(GetWindowLongPtrW(hwnd, GWL_EXSTYLE))

        // Calculate window size including frame using DPI-aware API
        let dpi = GetDpiForWindow(hwnd)
        var newRect = RECT(
            left: 0,
            top: 0,
            right: LONG(physical.width),
            bottom: LONG(physical.height)
        )
        AdjustWindowRectExForDpi(&newRect, dwStyle, false, dwExStyle, dpi)

        SetWindowPos(
            hwnd,
            nil,
            0, 0,
            newRect.right - newRect.left,
            newRect.bottom - newRect.top,
            UINT(SWP_NOMOVE | SWP_NOZORDER)
        )
    }

    borrowing func position() -> LogicalPosition {
        guard let hwnd = hwnd else { return LogicalPosition(x: 0, y: 0) }

        var rect = RECT()
        GetWindowRect(hwnd, &rect)
        let scaleFactor = scaleFactor()
        return PhysicalPosition(
            x: Int(rect.left),
            y: Int(rect.top)
        ).toLogical(scaleFactor: scaleFactor)
    }

    mutating func moveTo(_ position: borrowing LogicalPosition) {
        guard let hwnd = hwnd else { return }

        let physical = position.toPhysical(scaleFactor: scaleFactor())
        SetWindowPos(
            hwnd,
            nil,
            INT(physical.x),
            INT(physical.y),
            0, 0,
            UINT(SWP_NOSIZE | SWP_NOZORDER)
        )
    }

    mutating func setMinSize(_ size: borrowing LogicalSize?) {
        guard let hwnd = hwnd else { return }
        WinWindowRegistry.shared.setMinSize(size, for: hwnd)
    }

    mutating func setMaxSize(_ size: borrowing LogicalSize?) {
        guard let hwnd = hwnd else { return }
        WinWindowRegistry.shared.setMaxSize(size, for: hwnd)
    }

    mutating func requestFocus() {
        guard let hwnd = hwnd else { return }
        SetForegroundWindow(hwnd)
        SetFocus(hwnd)
    }

    borrowing func scaleFactor() -> Float {
        guard let hwnd = hwnd else { return 1.0 }
        let dpi = GetDpiForWindow(hwnd)
        return Float(dpi) / 96.0
    }
}

// MARK: - Sendable Conformance

extension WinWindow: @unchecked Sendable {}

#endif
