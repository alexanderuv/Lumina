#if os(Windows)
import WinSDK

/// WM_* message translation utilities for Windows.
///
/// These functions translate Windows messages to Lumina's cross-platform
/// Event types, handling coordinate conversion, modifier key mapping, and
/// virtual key code normalization.

// MARK: - Event Translation

/// Translate a Windows message to a Lumina Event.
///
/// This is called from the WndProc message handler.
///
/// - Parameters:
///   - msg: The Windows message ID
///   - wParam: First message parameter
///   - lParam: Second message parameter
///   - hwnd: The window handle
///   - windowID: The WindowID associated with this event
/// - Returns: Lumina Event, or nil if the event should be ignored
internal func translateWindowsMessage(
    msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    hwnd: HWND,
    for windowID: WindowID
) -> Event? {
    // Switch on message type
    switch msg {
    case UINT(WM_MOUSEMOVE):
        return translateMouseMove(wParam, lParam, hwnd, windowID)

    case UINT(WM_MOUSELEAVE):
        return translateMouseLeave(hwnd, windowID)

    case UINT(WM_LBUTTONDOWN):
        return translateMouseDown(.left, wParam, lParam, windowID)
    case UINT(WM_LBUTTONUP):
        return translateMouseUp(.left, wParam, lParam, windowID)

    case UINT(WM_RBUTTONDOWN):
        return translateMouseDown(.right, wParam, lParam, windowID)
    case UINT(WM_RBUTTONUP):
        return translateMouseUp(.right, wParam, lParam, windowID)

    case UINT(WM_MBUTTONDOWN):
        return translateMouseDown(.middle, wParam, lParam, windowID)
    case UINT(WM_MBUTTONUP):
        return translateMouseUp(.middle, wParam, lParam, windowID)

    case UINT(WM_MOUSEWHEEL):
        return translateMouseWheel(wParam, lParam, windowID, isHorizontal: false)

    case UINT(WM_MOUSEHWHEEL):
        return translateMouseWheel(wParam, lParam, windowID, isHorizontal: true)

    case UINT(WM_KEYDOWN), UINT(WM_SYSKEYDOWN):
        return translateKeyDown(wParam, lParam, windowID)
    case UINT(WM_KEYUP), UINT(WM_SYSKEYUP):
        return translateKeyUp(wParam, lParam, windowID)

    case UINT(WM_CHAR):
        return translateChar(wParam, windowID)

    case UINT(WM_SIZE):
        return translateSize(lParam, windowID)

    case UINT(WM_MOVE):
        return translateMove(lParam, windowID)

    case UINT(WM_SETFOCUS):
        return .window(.focused(windowID))

    case UINT(WM_KILLFOCUS):
        return .window(.unfocused(windowID))

    case UINT(WM_DPICHANGED):
        return translateDpiChanged(wParam, windowID)

    default:
        return nil
    }
}

// MARK: - Mouse Event Translation

private func translateMouseMove(
    _ wParam: WPARAM,
    _ lParam: LPARAM,
    _ hwnd: HWND,
    _ windowID: WindowID
) -> Event? {
    let position = extractMousePosition(lParam)

    // Check if we need to start tracking mouse leave
    let wasInWindow = WinWindowRegistry.shared.isMouseInWindow(for: hwnd)

    if !wasInWindow {
        // Mouse just entered - start tracking and synthesize enter event
        var tme = TRACKMOUSEEVENT()
        tme.cbSize = DWORD(MemoryLayout<TRACKMOUSEEVENT>.size)
        tme.dwFlags = DWORD(TME_LEAVE)
        tme.hwndTrack = hwnd
        tme.dwHoverTime = 0  // Not used for TME_LEAVE

        _ = TrackMouseEvent(&tme)
        WinWindowRegistry.shared.setMouseInWindow(true, for: hwnd)

        // Return enter event instead of move event
        return .pointer(.entered(windowID, position: position))
    }

    return .pointer(.moved(windowID, position: position))
}

private func translateMouseLeave(_ hwnd: HWND, _ windowID: WindowID) -> Event? {
    // Mark tracking as inactive
    WinWindowRegistry.shared.setMouseInWindow(false, for: hwnd)

    // Windows doesn't provide position for WM_MOUSELEAVE, use (0,0)
    // Note: This matches behavior of other platforms where leave position may not be accurate
    return .pointer(.left(windowID, position: LogicalPosition(x: 0, y: 0)))
}

private func translateMouseDown(
    _ button: MouseButton,
    _ wParam: WPARAM,
    _ lParam: LPARAM,
    _ windowID: WindowID
) -> Event? {
    let position = extractMousePosition(lParam)
    let modifiers = translateModifiers()
    return .pointer(.buttonPressed(windowID, button: button, position: position, modifiers: modifiers))
}

private func translateMouseUp(
    _ button: MouseButton,
    _ wParam: WPARAM,
    _ lParam: LPARAM,
    _ windowID: WindowID
) -> Event? {
    let position = extractMousePosition(lParam)
    let modifiers = translateModifiers()
    return .pointer(.buttonReleased(windowID, button: button, position: position, modifiers: modifiers))
}

private func translateMouseWheel(
    _ wParam: WPARAM,
    _ lParam: LPARAM,
    _ windowID: WindowID,
    isHorizontal: Bool
) -> Event? {
    // Extract wheel delta (high word of wParam) as signed value
    // Windows stores this as a signed SHORT, but HIWORD returns unsigned WORD
    // Use bitPattern initializer to reinterpret the bits as signed
    let highWord = HIWORD(DWORD(wParam))
    let delta = Int16(bitPattern: highWord)
    let normalizedDelta = Float(delta) / 120.0  // Windows reports in multiples of 120

    if isHorizontal {
        // Horizontal scroll (WM_MOUSEHWHEEL)
        return .pointer(.wheel(windowID, deltaX: normalizedDelta, deltaY: 0))
    } else {
        // Vertical scroll (WM_MOUSEWHEEL) - negate for Lumina convention
        return .pointer(.wheel(windowID, deltaX: 0, deltaY: -normalizedDelta))
    }
}

// MARK: - Keyboard Event Translation

private func translateKeyDown(
    _ wParam: WPARAM,
    _ lParam: LPARAM,
    _ windowID: WindowID
) -> Event? {
    let keyCode = translateKeyCode(wParam, lParam)
    let modifiers = translateModifiers()
    return .keyboard(.keyDown(windowID, key: keyCode, modifiers: modifiers))
}

private func translateKeyUp(
    _ wParam: WPARAM,
    _ lParam: LPARAM,
    _ windowID: WindowID
) -> Event? {
    let keyCode = translateKeyCode(wParam, lParam)
    let modifiers = translateModifiers()
    return .keyboard(.keyUp(windowID, key: keyCode, modifiers: modifiers))
}

private func translateChar(
    _ wParam: WPARAM,
    _ windowID: WindowID
) -> Event? {
    // wParam contains the UTF-16 character code
    let utf16Code = UInt16(wParam & 0xFFFF)

    // Convert UTF-16 to String
    let char = String(utf16CodeUnits: [utf16Code], count: 1)

    // Ignore control characters (ASCII 0-31 and 127)
    guard !char.isEmpty, let scalar = char.unicodeScalars.first, scalar.value >= 32 && scalar.value != 127 else {
        return nil
    }

    return .keyboard(.textInput(windowID, text: char))
}

// MARK: - Window Event Translation

private func translateSize(
    _ lParam: LPARAM,
    _ windowID: WindowID
) -> Event? {
    let width = Float(LOWORD(DWORD(lParam)))
    let height = Float(HIWORD(DWORD(lParam)))
    let size = LogicalSize(width: width, height: height)
    return .window(.resized(windowID, size))
}

private func translateMove(
    _ lParam: LPARAM,
    _ windowID: WindowID
) -> Event? {
    let x = Float(Int16(LOWORD(DWORD(lParam))))
    let y = Float(Int16(HIWORD(DWORD(lParam))))
    let position = LogicalPosition(x: x, y: y)
    return .window(.moved(windowID, position))
}

private func translateDpiChanged(
    _ wParam: WPARAM,
    _ windowID: WindowID
) -> Event? {
    // For now, we don't track the old DPI, so we can't provide oldFactor
    // In a future milestone, we could track this per-window
    let newDpi = HIWORD(DWORD(wParam))
    let newFactor = Float(newDpi) / 96.0

    // We use 1.0 as oldFactor since we don't track it yet
    return .window(.scaleFactorChanged(windowID, oldFactor: 1.0, newFactor: newFactor))
}

// MARK: - Helper Functions

/// Translate virtual key code to Lumina KeyCode.
///
/// Windows uses virtual key codes (VK_*), which need to be converted
/// to scan codes for platform-normalized key codes.
private func translateKeyCode(_ vkCode: WPARAM, _ lParam: LPARAM) -> KeyCode {
    // Extract scan code from lParam (bits 16-23)
    let scanCode = (lParam >> 16) & 0xFF

    // Check for extended key flag (bit 24)
    let isExtended = (lParam & 0x01000000) != 0

    // Combine scan code with extended flag
    let normalizedCode = UInt32(scanCode) | (isExtended ? 0xE000 : 0)

    return KeyCode(rawValue: normalizedCode)
}

/// Translate Windows modifier key state.
private func translateModifiers() -> ModifierKeys {
    var modifiers: ModifierKeys = []

    // GetKeyState returns SHORT, high bit set means key is down
    if GetKeyState(Int32(VK_SHIFT)) < 0 {
        modifiers.insert(.shift)
    }
    if GetKeyState(Int32(VK_CONTROL)) < 0 {
        modifiers.insert(.control)
    }
    if GetKeyState(Int32(VK_MENU)) < 0 {
        modifiers.insert(.alt)
    }
    if GetKeyState(Int32(VK_LWIN)) < 0 || GetKeyState(Int32(VK_RWIN)) < 0 {
        modifiers.insert(.command)
    }

    return modifiers
}

/// Extract mouse position from lParam.
private func extractMousePosition(_ lParam: LPARAM) -> LogicalPosition {
    // Extract x and y from lParam (low word = x, high word = y)
    let x = Int16(LOWORD(DWORD(lParam)))
    let y = Int16(HIWORD(DWORD(lParam)))

    return LogicalPosition(x: Float(x), y: Float(y))
}

// MARK: - Win32 Helper Macros

/// Extract low-order word from a DWORD
private func LOWORD(_ l: DWORD) -> WORD {
    return WORD(l & 0xFFFF)
}

/// Extract high-order word from a DWORD
private func HIWORD(_ l: DWORD) -> WORD {
    return WORD((l >> 16) & 0xFFFF)
}

#endif
