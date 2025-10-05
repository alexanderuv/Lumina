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
/// This would be called from the WndProc message handler.
///
/// - Parameters:
///   - msg: The Windows message ID
///   - wParam: First message parameter
///   - lParam: Second message parameter
///   - windowID: The WindowID associated with this event
/// - Returns: Lumina Event, or nil if the event should be ignored
internal func translateWindowsMessage(
    msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    for windowID: WindowID
) -> Event? {
    // Switch on message type
    // switch msg {
    // case WM_MOUSEMOVE:
    //     return translateMouseMove(wParam, lParam, windowID)
    // case WM_LBUTTONDOWN:
    //     return translateMouseDown(.left, wParam, lParam, windowID)
    // case WM_LBUTTONUP:
    //     return translateMouseUp(.left, wParam, lParam, windowID)
    // case WM_RBUTTONDOWN:
    //     return translateMouseDown(.right, wParam, lParam, windowID)
    // case WM_RBUTTONUP:
    //     return translateMouseUp(.right, wParam, lParam, windowID)
    // case WM_MBUTTONDOWN:
    //     return translateMouseDown(.middle, wParam, lParam, windowID)
    // case WM_MBUTTONUP:
    //     return translateMouseUp(.middle, wParam, lParam, windowID)
    // case WM_MOUSEWHEEL:
    //     return translateMouseWheel(wParam, lParam, windowID)
    // case WM_KEYDOWN:
    //     return translateKeyDown(wParam, lParam, windowID)
    // case WM_KEYUP:
    //     return translateKeyUp(wParam, lParam, windowID)
    // case WM_CHAR:
    //     return translateChar(wParam, windowID)
    // default:
    //     return nil
    // }

    return nil
}

// MARK: - Mouse Event Translation

// private func translateMouseMove(
//     _ wParam: WPARAM,
//     _ lParam: LPARAM,
//     _ windowID: WindowID
// ) -> Event? {
//     let position = extractMousePosition(lParam)
//     return .pointer(.moved(windowID, position: position))
// }

// MARK: - Keyboard Event Translation

/// Translate virtual key code to Lumina KeyCode.
///
/// Windows uses virtual key codes (VK_*), which need to be converted
/// to scan codes for platform-normalized key codes.
// private func translateKeyCode(_ vkCode: WPARAM) -> KeyCode {
//     // MapVirtualKey to get scan code
//     let scanCode = MapVirtualKey(UINT(vkCode), MAPVK_VK_TO_VSC)
//     return KeyCode(rawValue: UInt32(scanCode))
// }

/// Translate Windows modifier key state.
// private func translateModifiers() -> ModifierKeys {
//     var modifiers: ModifierKeys = []
//
//     if GetKeyState(VK_SHIFT) & 0x8000 != 0 {
//         modifiers.insert(.shift)
//     }
//     if GetKeyState(VK_CONTROL) & 0x8000 != 0 {
//         modifiers.insert(.control)
//     }
//     if GetKeyState(VK_MENU) & 0x8000 != 0 {
//         modifiers.insert(.alt)
//     }
//     if GetKeyState(VK_LWIN) & 0x8000 != 0 || GetKeyState(VK_RWIN) & 0x8000 != 0 {
//         modifiers.insert(.command)
//     }
//
//     return modifiers
// }

// MARK: - Helper Functions

/// Extract mouse position from lParam.
// private func extractMousePosition(_ lParam: LPARAM) -> LogicalPosition {
//     let x = GET_X_LPARAM(lParam)
//     let y = GET_Y_LPARAM(lParam)
//     return LogicalPosition(x: Float(x), y: Float(y))
// }

#endif
