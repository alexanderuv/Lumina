#if os(Linux)
import CXCBLinux

/// X11 input event translation layer.
///
/// This module provides static translation functions that convert XCB input events
/// (button, motion, key, wheel) into Lumina's cross-platform Event types. It handles:
/// - Mouse button press/release → PointerEvent
/// - Mouse motion → PointerEvent.moved
/// - Keyboard press/release with XKB keymap → KeyboardEvent
/// - Mouse wheel scrolling → PointerEvent.wheel
/// - Modifier key state tracking
///
/// All translations preserve coordinate systems (X11 uses top-left origin, same as Lumina)
/// and normalize button/key codes to platform-agnostic representations.
///
/// Example usage:
/// ```swift
/// // In event loop:
/// let responseType = xcb_event_response_type_shim(xcbEvent) & 0x7f
/// switch Int32(responseType) {
/// case XCB_BUTTON_PRESS:
///     if let event = X11Input.translateButtonEvent(xcbEvent, windowID, pressed: true) {
///         eventQueue.append(.pointer(event))
///     }
/// case XCB_MOTION_NOTIFY:
///     if let event = X11Input.translateMotionEvent(xcbEvent, windowID) {
///         eventQueue.append(.pointer(event))
///     }
/// case XCB_KEY_PRESS:
///     if let event = X11Input.translateKeyEvent(xcbEvent, windowID, pressed: true, xkbState: xkbState) {
///         eventQueue.append(.keyboard(event))
///     }
/// }
/// ```
@MainActor
public enum X11Input {

    // MARK: - Button Event Translation

    /// Translate XCB button press/release event to PointerEvent.
    ///
    /// X11 button codes:
    /// - 1 = Left button
    /// - 2 = Middle button
    /// - 3 = Right button
    /// - 4/5 = Scroll wheel (handled separately by translateScrollEvent)
    /// - 8/9 = Additional buttons (not supported in Milestone 1)
    ///
    /// - Parameters:
    ///   - xcbEvent: Raw XCB event pointer (must be xcb_button_press_event_t or xcb_button_release_event_t)
    ///   - windowID: The Lumina window ID this event is associated with
    ///   - pressed: true for button press, false for button release
    /// - Returns: PointerEvent if the button is supported, nil otherwise
    ///
    /// Example:
    /// ```swift
    /// let buttonEvent = xcbEvent.withMemoryRebound(to: xcb_button_press_event_t.self, capacity: 1) { ptr in
    ///     X11Input.translateButtonEvent(ptr, windowID: windowID, pressed: true)
    /// }
    /// ```
    public static func translateButtonEvent(
        _ xcbEvent: UnsafeMutablePointer<xcb_generic_event_t>,
        windowID: WindowID,
        pressed: Bool
    ) -> PointerEvent? {
        let buttonEvent = xcbEvent.withMemoryRebound(to: xcb_button_press_event_t.self, capacity: 1) { $0.pointee }

        // X11 buttons 4 and 5 are scroll wheel (handled separately)
        guard buttonEvent.detail != 4 && buttonEvent.detail != 5 else {
            return nil
        }

        // Translate X11 button to MouseButton
        let button: MouseButton
        switch buttonEvent.detail {
        case 1:
            button = .left
        case 2:
            button = .middle
        case 3:
            button = .right
        case 8:  // X11 button 8 (typically "back")
            button = .button4
        case 9:  // X11 button 9 (typically "forward")
            button = .button5
        case 6:  // X11 button 6
            button = .button6
        case 7:  // X11 button 7
            button = .button7
        case 10: // X11 button 10
            button = .button8
        default:
            // Unsupported button
            return nil
        }

        // Extract modifiers from state field
        var modifiers: ModifierKeys = []
        let state = buttonEvent.state
        if state & UInt16(XCB_MOD_MASK_SHIFT.rawValue) != 0 {
            modifiers.insert(.shift)
        }
        if state & UInt16(XCB_MOD_MASK_CONTROL.rawValue) != 0 {
            modifiers.insert(.control)
        }
        if state & UInt16(XCB_MOD_MASK_1.rawValue) != 0 {  // Alt
            modifiers.insert(.alt)
        }
        if state & UInt16(XCB_MOD_MASK_4.rawValue) != 0 {  // Super/Command
            modifiers.insert(.command)
        }

        // Extract position (X11 uses top-left origin, same as Lumina)
        let position = LogicalPosition(
            x: Float(buttonEvent.event_x),
            y: Float(buttonEvent.event_y)
        )

        if pressed {
            return .buttonPressed(windowID, button: button, position: position, modifiers: modifiers)
        } else {
            return .buttonReleased(windowID, button: button, position: position, modifiers: modifiers)
        }
    }

    // MARK: - Motion Event Translation

    /// Translate XCB motion notify event to PointerEvent.moved.
    ///
    /// Motion events are generated continuously as the pointer moves within the window.
    /// X11 may coalesce multiple motion events for performance.
    ///
    /// - Parameters:
    ///   - xcbEvent: Raw XCB event pointer (must be xcb_motion_notify_event_t)
    ///   - windowID: The Lumina window ID this event is associated with
    /// - Returns: PointerEvent.moved with the current pointer position
    ///
    /// Example:
    /// ```swift
    /// if let motionEvent = X11Input.translateMotionEvent(xcbEvent, windowID: windowID) {
    ///     print("Pointer at (\(motionEvent.position.x), \(motionEvent.position.y))")
    /// }
    /// ```
    public static func translateMotionEvent(
        _ xcbEvent: UnsafeMutablePointer<xcb_generic_event_t>,
        windowID: WindowID
    ) -> PointerEvent? {
        let motionEvent = xcbEvent.withMemoryRebound(to: xcb_motion_notify_event_t.self, capacity: 1) { $0.pointee }

        // Extract position (X11 uses top-left origin, same as Lumina)
        let position = LogicalPosition(
            x: Float(motionEvent.event_x),
            y: Float(motionEvent.event_y)
        )

        return .moved(windowID, position: position)
    }

    // MARK: - Scroll Event Translation

    /// Translate XCB button press event to PointerEvent.wheel if it's a scroll event.
    ///
    /// X11 represents mouse wheel scrolling as button press events:
    /// - Button 4 = Scroll up (negative deltaY)
    /// - Button 5 = Scroll down (positive deltaY)
    /// - Buttons 6/7 = Horizontal scroll (not widely supported)
    ///
    /// Each click generates a fixed delta of approximately 1.0 units.
    ///
    /// - Parameters:
    ///   - xcbEvent: Raw XCB event pointer (must be xcb_button_press_event_t)
    ///   - windowID: The Lumina window ID this event is associated with
    /// - Returns: PointerEvent.wheel if this is a scroll event, nil otherwise
    ///
    /// Example:
    /// ```swift
    /// if let scrollEvent = X11Input.translateScrollEvent(xcbEvent, windowID: windowID) {
    ///     print("Scroll delta: \(scrollEvent.deltaY)")
    /// }
    /// ```
    public static func translateScrollEvent(
        _ xcbEvent: UnsafeMutablePointer<xcb_generic_event_t>,
        windowID: WindowID
    ) -> PointerEvent? {
        let buttonEvent = xcbEvent.withMemoryRebound(to: xcb_button_press_event_t.self, capacity: 1) { $0.pointee }

        // X11 scroll wheel encoding
        let deltaX: Float
        let deltaY: Float

        switch buttonEvent.detail {
        case 4:
            // Scroll up (negative Y per Lumina convention: positive = down)
            deltaX = 0.0
            deltaY = -1.0
        case 5:
            // Scroll down (positive Y per Lumina convention: positive = down)
            deltaX = 0.0
            deltaY = 1.0
        case 6:
            // Scroll left (not widely supported)
            deltaX = -1.0
            deltaY = 0.0
        case 7:
            // Scroll right (not widely supported)
            deltaX = 1.0
            deltaY = 0.0
        default:
            // Not a scroll event
            return nil
        }

        return .wheel(windowID, deltaX: deltaX, deltaY: deltaY)
    }

    // MARK: - Keyboard Event Translation

    /// Translate XCB key press/release event to KeyboardEvent with XKB keymap interpretation.
    ///
    /// This function performs several steps:
    /// 1. Extract X11 keycode from event
    /// 2. Query XKB state for modifier keys
    /// 3. Translate keycode to Lumina KeyCode (using raw scan code)
    /// 4. Optionally generate text input for character keys
    ///
    /// X11 keycodes are hardware scan codes + 8 offset. XKB provides layout-aware
    /// interpretation of keys.
    ///
    /// - Parameters:
    ///   - xcbEvent: Raw XCB event pointer (must be xcb_key_press_event_t or xcb_key_release_event_t)
    ///   - windowID: The Lumina window ID this event is associated with
    ///   - pressed: true for key press, false for key release
    ///   - xkbState: XKB keyboard state for modifier and symbol interpretation (optional)
    /// - Returns: KeyboardEvent (keyDown/keyUp/textInput) if successful, nil on error
    ///
    /// Example:
    /// ```swift
    /// if let keyEvent = X11Input.translateKeyEvent(xcbEvent, windowID: windowID, pressed: true, xkbState: xkbState) {
    ///     switch keyEvent {
    ///     case .keyDown(_, let key, let modifiers):
    ///         print("Key \(key.rawValue) pressed with modifiers \(modifiers)")
    ///     case .textInput(_, let text):
    ///         print("Text input: \(text)")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public static func translateKeyEvent(
        _ xcbEvent: UnsafeMutablePointer<xcb_generic_event_t>,
        windowID: WindowID,
        pressed: Bool,
        xkbState: OpaquePointer?
    ) -> KeyboardEvent? {
        let keyEvent = xcbEvent.withMemoryRebound(to: xcb_key_press_event_t.self, capacity: 1) { $0.pointee }

        // X11 keycode (hardware scan code + 8)
        let x11Keycode = keyEvent.detail

        // Extract modifier state from XCB event
        let modifiers = translateModifiers(keyEvent.state)

        // Use X11 keycode directly as Lumina KeyCode (platform-normalized scan code)
        // Future: Could map to common key constants like KeyCode.escape
        let keyCode = KeyCode(rawValue: UInt32(x11Keycode))

        // Generate keyDown/keyUp event
        if pressed {
            return .keyDown(windowID, key: keyCode, modifiers: modifiers)
        } else {
            return .keyUp(windowID, key: keyCode, modifiers: modifiers)
        }
    }

    /// Translate XCB key press event to text input (separate from key event).
    ///
    /// This function should be called after translateKeyEvent to generate text input
    /// for character-producing keys. It uses XKB to interpret the key press according
    /// to the current keyboard layout.
    ///
    /// - Parameters:
    ///   - xcbEvent: Raw XCB event pointer (must be xcb_key_press_event_t)
    ///   - windowID: The Lumina window ID this event is associated with
    ///   - xkbState: XKB keyboard state for symbol interpretation
    /// - Returns: KeyboardEvent.textInput if this key produces text, nil otherwise
    ///
    /// Example:
    /// ```swift
    /// if let textEvent = X11Input.translateTextInput(xcbEvent, windowID: windowID, xkbState: xkbState) {
    ///     case .textInput(_, let text):
    ///         insertText(text)
    /// }
    /// ```
    public static func translateTextInput(
        _ xcbEvent: UnsafeMutablePointer<xcb_generic_event_t>,
        windowID: WindowID,
        xkbState: OpaquePointer?
    ) -> KeyboardEvent? {
        guard let xkbState = xkbState else {
            return nil
        }

        let keyEvent = xcbEvent.withMemoryRebound(to: xcb_key_press_event_t.self, capacity: 1) { $0.pointee }
        let x11Keycode = keyEvent.detail

        // Convert keysym to UTF-8 text
        let xkbKeycode = xkb_keycode_t(x11Keycode)
        var buffer = [UInt8](repeating: 0, count: 32)
        let length = xkb_state_key_get_utf8(xkbState, xkbKeycode, &buffer, buffer.count)

        if length > 0 && length < buffer.count {
            let textBytes = buffer.prefix(Int(length))
            let text = String(decoding: textBytes, as: UTF8.self)
            // Only generate text input for printable characters
            if !text.isEmpty && text.rangeOfCharacter(from: .controlCharacters) == nil {
                return .textInput(windowID, text: text)
            }
        }

        return nil
    }

    // MARK: - Modifier Key Translation

    /// Translate X11 modifier state bitmask to ModifierKeys.
    ///
    /// X11 modifier state bits (from xcb/xproto.h):
    /// - XCB_MOD_MASK_SHIFT (1 << 0) = Shift
    /// - XCB_MOD_MASK_CONTROL (1 << 2) = Control
    /// - XCB_MOD_MASK_1 (1 << 3) = Mod1 (typically Alt)
    /// - XCB_MOD_MASK_4 (1 << 6) = Mod4 (typically Super/Windows/Command)
    ///
    /// - Parameter state: X11 modifier state bitmask
    /// - Returns: ModifierKeys option set
    ///
    /// Example:
    /// ```swift
    /// let modifiers = X11Input.translateModifiers(keyEvent.state)
    /// if modifiers.contains(.control) {
    ///     print("Control key is held")
    /// }
    /// ```
    public static func translateModifiers(_ state: UInt16) -> ModifierKeys {
        var modifiers = ModifierKeys()

        // Shift (Mod_MASK_SHIFT = 1 << 0)
        if state & (1 << 0) != 0 {
            modifiers.insert(.shift)
        }

        // Control (MOD_MASK_CONTROL = 1 << 2)
        if state & (1 << 2) != 0 {
            modifiers.insert(.control)
        }

        // Alt (MOD_MASK_1 = 1 << 3, typically mapped to Alt)
        if state & (1 << 3) != 0 {
            modifiers.insert(.alt)
        }

        // Super/Windows/Command (MOD_MASK_4 = 1 << 6, typically mapped to Super)
        if state & (1 << 6) != 0 {
            modifiers.insert(.command)
        }

        return modifiers
    }
}

#endif
