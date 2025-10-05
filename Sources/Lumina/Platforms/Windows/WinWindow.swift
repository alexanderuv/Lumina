#if os(Windows)
import WinSDK

/// Windows implementation of WindowBackend using HWND.
///
/// This implementation wraps a Windows window handle (HWND) and provides
/// Lumina's cross-platform window interface. It handles DPI scaling,
/// window styles, and Win32 API calls.
@MainActor
internal struct WinWindow: WindowBackend {
    let id: WindowID
    // private var hwnd: HWND

    /// Create a new Windows window.
    ///
    /// - Parameters:
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether the window can be resized by the user
    /// - Returns: Result containing WinWindow or LuminaError
    static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool
    ) -> Result<WinWindow, LuminaError> {
        // Configure window style
        // let dwStyle: DWORD = resizable
        //     ? WS_OVERLAPPEDWINDOW
        //     : (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU)
        //
        // let hwnd = CreateWindowEx(
        //     0,                          // dwExStyle
        //     className,                  // Window class
        //     title.utf16CString,         // Window title
        //     dwStyle,
        //     CW_USEDEFAULT, CW_USEDEFAULT,
        //     Int32(size.width), Int32(size.height),
        //     nil, nil, hInstance, nil
        // )
        //
        // guard hwnd != nil else {
        //     return .failure(.windowCreationFailed(reason: "CreateWindowEx failed"))
        // }

        let windowID = WindowID()
        return .failure(.platformError(code: 0, message: "Windows platform not implemented"))
    }

    mutating func show() {
        // ShowWindow(hwnd, SW_SHOW)
    }

    mutating func hide() {
        // ShowWindow(hwnd, SW_HIDE)
    }

    consuming func close() {
        // DestroyWindow(hwnd)
    }

    mutating func setTitle(_ title: borrowing String) {
        // SetWindowText(hwnd, title.utf16CString)
    }

    borrowing func size() -> LogicalSize {
        // var rect = RECT()
        // GetClientRect(hwnd, &rect)
        // let scaleFactor = scaleFactor()
        // return PhysicalSize(
        //     width: Int(rect.right - rect.left),
        //     height: Int(rect.bottom - rect.top)
        // ).toLogical(scaleFactor: scaleFactor)

        return LogicalSize(width: 0, height: 0)
    }

    mutating func resize(_ size: borrowing LogicalSize) {
        // let physical = size.toPhysical(scaleFactor: scaleFactor())
        // SetWindowPos(hwnd, nil, 0, 0, Int32(physical.width), Int32(physical.height),
        //              SWP_NOMOVE | SWP_NOZORDER)
    }

    borrowing func position() -> LogicalPosition {
        // var rect = RECT()
        // GetWindowRect(hwnd, &rect)
        // let scaleFactor = scaleFactor()
        // return PhysicalPosition(
        //     x: Int(rect.left),
        //     y: Int(rect.top)
        // ).toLogical(scaleFactor: scaleFactor)

        return LogicalPosition(x: 0, y: 0)
    }

    mutating func moveTo(_ position: borrowing LogicalPosition) {
        // let physical = position.toPhysical(scaleFactor: scaleFactor())
        // SetWindowPos(hwnd, nil, Int32(physical.x), Int32(physical.y), 0, 0,
        //              SWP_NOSIZE | SWP_NOZORDER)
    }

    mutating func setMinSize(_ size: borrowing LogicalSize?) {
        // Handle in WM_GETMINMAXINFO message
    }

    mutating func setMaxSize(_ size: borrowing LogicalSize?) {
        // Handle in WM_GETMINMAXINFO message
    }

    mutating func requestFocus() {
        // SetForegroundWindow(hwnd)
    }

    borrowing func scaleFactor() -> Float {
        // let dpi = GetDpiForWindow(hwnd)
        // return Float(dpi) / 96.0

        return 1.0
    }
}

// MARK: - Sendable Conformance

extension WinWindow: @unchecked Sendable {}

#endif
