#if os(Windows)
import WinSDK

// Windows cursor resource IDs
private let IDC_ARROW: Int = 0x7F00
private let IDC_IBEAM: Int = 0x7F01
private let IDC_CROSS: Int = 0x7F03
private let IDC_SIZENWSE: Int = 0x7F82
private let IDC_SIZENESW: Int = 0x7F83
private let IDC_SIZEWE: Int = 0x7F84
private let IDC_SIZENS: Int = 0x7F85
private let IDC_HAND: Int = 0x7F89

/// Windows implementation of LuminaCursor using Win32 cursor APIs
@MainActor
internal struct WinCursor: LuminaCursor {
    func set(_ cursor: SystemCursor) {
        let cursorId: Int

        switch cursor {
        case .arrow:
            cursorId = IDC_ARROW
        case .hand:
            cursorId = IDC_HAND
        case .ibeam:
            cursorId = IDC_IBEAM
        case .crosshair:
            cursorId = IDC_CROSS
        case .resizeNS:
            cursorId = IDC_SIZENS
        case .resizeEW:
            cursorId = IDC_SIZEWE
        case .resizeNESW:
            cursorId = IDC_SIZENESW
        case .resizeNWSE:
            cursorId = IDC_SIZENWSE
        }

        // MAKEINTRESOURCEW equivalent: cast integer ID to pointer
        if let cursorHandle = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: cursorId)) {
            SetCursor(cursorHandle)
        }
    }

    func hide() {
        ShowCursor(false)
    }

    func show() {
        ShowCursor(true)
    }
}

#endif
