/// Event types for window, input, and application lifecycle.
///
/// Lumina's event system provides a unified, platform-agnostic representation
/// of all window and input events. All event types are Sendable value types,
/// enabling safe cross-thread event passing and borrowing-based dispatch.

/// Main event type representing all possible events in Lumina.
///
/// Events are dispatched through the application's event loop and can be
/// processed using pattern matching. All events include the WindowID they're
/// associated with (except user events, which are application-wide).
///
/// Example:
/// ```swift
/// while try app.poll() {
///     // Events are available via platform-specific mechanism
///     // (This will be exposed through a callback API in the future)
/// }
/// ```
public enum Event: Sendable {
    /// Window lifecycle and state event
    case window(WindowEvent)

    /// Pointer (mouse/trackpad) event
    case pointer(PointerEvent)

    /// Keyboard event
    case keyboard(KeyboardEvent)

    /// User-defined custom event
    case user(UserEvent)
}

// MARK: - Window Events

/// Window lifecycle and state change events.
///
/// Window events track the creation, destruction, and state changes of windows.
/// These events are essential for managing window lifecycle and responding to
/// system-initiated changes (like user resizing or moving windows).
///
/// Example:
/// ```swift
/// if case .window(.resized(let windowID, let newSize)) = event {
///     print("Window \(windowID) resized to \(newSize)")
///     // Update internal state, trigger re-layout, etc.
/// }
/// ```
public enum WindowEvent: Sendable {
    /// Window was created and is ready for use.
    ///
    /// This event is sent immediately after successful window creation,
    /// before the window is shown.
    ///
    /// - Parameter windowID: ID of the newly created window
    case created(WindowID)

    /// Window was closed by the user or programmatically.
    ///
    /// After this event, the window is no longer valid and should not be used.
    /// Clean up any resources associated with this window.
    ///
    /// - Parameter windowID: ID of the closed window
    case closed(WindowID)

    /// Window size changed (user resize or programmatic).
    ///
    /// This event is sent after the window has been resized, either by the user
    /// dragging the window edges or programmatic resize operations.
    ///
    /// - Parameters:
    ///   - windowID: ID of the resized window
    ///   - size: New logical size of the window content area
    case resized(WindowID, LogicalSize)

    /// Window position changed (user drag or programmatic).
    ///
    /// This event is sent after the window has been moved, either by the user
    /// dragging the title bar or programmatic move operations.
    ///
    /// - Parameters:
    ///   - windowID: ID of the moved window
    ///   - position: New logical position of the window's top-left corner
    case moved(WindowID, LogicalPosition)

    /// Window gained keyboard focus.
    ///
    /// This event is sent when the window becomes the active window and will
    /// receive keyboard input. Only one window can have focus at a time.
    ///
    /// - Parameter windowID: ID of the focused window
    case focused(WindowID)

    /// Window lost keyboard focus.
    ///
    /// This event is sent when the window is no longer the active window.
    /// Keyboard input will be directed to another window (or no window).
    ///
    /// - Parameter windowID: ID of the unfocused window
    case unfocused(WindowID)

    /// Window's scale factor changed (moved to different monitor).
    ///
    /// This event is sent when the window moves between monitors with different
    /// DPI settings, or when the system DPI settings change. Applications should
    /// update their rendering to account for the new scale factor.
    ///
    /// - Parameters:
    ///   - windowID: ID of the affected window
    ///   - oldFactor: Previous scale factor
    ///   - newFactor: New scale factor
    case scaleFactorChanged(WindowID, oldFactor: Float, newFactor: Float)
}

// MARK: - Pointer Events

/// Pointer (mouse/trackpad) input events.
///
/// Pointer events track mouse and trackpad input, including movement, button
/// presses, and scroll wheel operations. All positions are in logical coordinates
/// relative to the window's content area.
///
/// Example:
/// ```swift
/// if case .pointer(.buttonPressed(let windowID, let button, let position)) = event {
///     print("Button \(button) pressed at \(position) in window \(windowID)")
///     // Handle click, start drag operation, etc.
/// }
/// ```
public enum PointerEvent: Sendable {
    /// Pointer moved within the window.
    ///
    /// This event is sent continuously as the pointer moves within the window's
    /// content area. High-frequency events may be coalesced by the platform.
    ///
    /// - Parameters:
    ///   - windowID: ID of the window containing the pointer
    ///   - position: Logical position relative to window's top-left corner
    case moved(WindowID, position: LogicalPosition)

    /// Pointer entered the window's content area.
    ///
    /// This event is sent when the pointer first enters the window from outside.
    /// Use this to change cursor appearance or show hover states.
    ///
    /// - Parameter windowID: ID of the window the pointer entered
    case entered(WindowID)

    /// Pointer left the window's content area.
    ///
    /// This event is sent when the pointer leaves the window's bounds.
    /// Use this to reset hover states or cursor appearance.
    ///
    /// - Parameter windowID: ID of the window the pointer left
    case left(WindowID)

    /// Mouse button was pressed.
    ///
    /// This event is sent when a mouse button transitions from released to pressed.
    /// Button press events are always delivered to the window under the pointer.
    ///
    /// - Parameters:
    ///   - windowID: ID of the window containing the pointer
    ///   - button: Which mouse button was pressed
    ///   - position: Logical position where the press occurred
    case buttonPressed(WindowID, button: MouseButton, position: LogicalPosition)

    /// Mouse button was released.
    ///
    /// This event is sent when a mouse button transitions from pressed to released.
    /// Release events are delivered to the window that received the corresponding
    /// press event, even if the pointer has moved outside the window.
    ///
    /// - Parameters:
    ///   - windowID: ID of the window that captured the button press
    ///   - button: Which mouse button was released
    ///   - position: Logical position where the release occurred
    case buttonReleased(WindowID, button: MouseButton, position: LogicalPosition)

    /// Mouse wheel or trackpad scroll occurred.
    ///
    /// This event is sent when the user scrolls using a mouse wheel or trackpad.
    /// Delta values are in logical units and may be fractional for high-precision
    /// trackpad scrolling.
    ///
    /// - Parameters:
    ///   - windowID: ID of the window containing the pointer
    ///   - deltaX: Horizontal scroll amount (positive = right, negative = left)
    ///   - deltaY: Vertical scroll amount (positive = down, negative = up)
    case wheel(WindowID, deltaX: Float, deltaY: Float)
}

/// Mouse button enumeration.
///
/// Represents the physical mouse buttons. Additional buttons beyond these three
/// are not currently supported in Milestone 0.
public enum MouseButton: Sendable {
    /// Left (primary) mouse button
    case left

    /// Right (secondary/context) mouse button
    case right

    /// Middle (wheel) mouse button
    case middle
}

// MARK: - Keyboard Events

/// Keyboard input events.
///
/// Keyboard events track physical key presses and releases, as well as
/// text input for characters. Key codes are platform-normalized scan codes
/// that represent physical key positions, while text input provides the
/// actual character produced (accounting for keyboard layout).
///
/// Example:
/// ```swift
/// if case .keyboard(.keyDown(let windowID, let key, let modifiers)) = event {
///     if key == .escape {
///         print("Escape key pressed")
///     }
///     if modifiers.contains(.command) {
///         print("Command key is held")
///     }
/// }
/// ```
public enum KeyboardEvent: Sendable {
    /// Physical key was pressed.
    ///
    /// This event is sent when a key transitions from released to pressed.
    /// Key repeat events (when holding a key) also generate keyDown events
    /// on most platforms.
    ///
    /// - Parameters:
    ///   - windowID: ID of the focused window receiving input
    ///   - key: Physical key code (platform-normalized)
    ///   - modifiers: Current state of modifier keys
    case keyDown(WindowID, key: KeyCode, modifiers: ModifierKeys)

    /// Physical key was released.
    ///
    /// This event is sent when a key transitions from pressed to released.
    ///
    /// - Parameters:
    ///   - windowID: ID of the focused window receiving input
    ///   - key: Physical key code (platform-normalized)
    ///   - modifiers: Current state of modifier keys
    case keyUp(WindowID, key: KeyCode, modifiers: ModifierKeys)

    /// Text input was received.
    ///
    /// This event is sent when a key press produces actual text characters,
    /// accounting for the current keyboard layout, input method, and dead keys.
    /// Use this for text editing rather than key codes.
    ///
    /// Note: In Milestone 0, only Latin text input is fully supported.
    /// IME support for Asian languages will be added in a future milestone.
    ///
    /// - Parameters:
    ///   - windowID: ID of the focused window receiving input
    ///   - text: UTF-8 encoded text produced by the key press
    case textInput(WindowID, text: String)
}

/// Physical key code (platform-normalized).
///
/// KeyCode represents the physical position of a key on the keyboard,
/// independent of the current keyboard layout. This allows handling
/// keys consistently across different layouts (e.g., QWERTY vs AZERTY).
///
/// In Milestone 0, we use raw scan codes. Future milestones will add
/// named constants for common keys (Escape, Enter, Arrow keys, etc.).
///
/// Example:
/// ```swift
/// let escapeKey = KeyCode(rawValue: 0x35)  // macOS scan code for Escape
/// ```
public struct KeyCode: Sendable, Hashable {
    /// Platform-normalized scan code
    public let rawValue: UInt32

    /// Create a key code from a raw scan code.
    ///
    /// - Parameter rawValue: Platform-normalized scan code
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

extension KeyCode {
    // Common key codes (platform-normalized)
    // These will be expanded in future milestones

    /// Escape key
    public static let escape = KeyCode(rawValue: 0x35)

    /// Return/Enter key
    public static let `return` = KeyCode(rawValue: 0x24)

    /// Tab key
    public static let tab = KeyCode(rawValue: 0x30)

    /// Space bar
    public static let space = KeyCode(rawValue: 0x31)

    /// Backspace/Delete key
    public static let backspace = KeyCode(rawValue: 0x33)
}

/// Modifier key state (bitfield).
///
/// ModifierKeys represents the current state of keyboard modifier keys
/// (Shift, Control, Alt, Command/Windows) using an option set. Multiple
/// modifiers can be active simultaneously.
///
/// Example:
/// ```swift
/// let modifiers: ModifierKeys = [.command, .shift]
/// if modifiers.contains(.command) {
///     print("Command key is held")
/// }
/// ```
public struct ModifierKeys: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Shift key (either left or right)
    public static let shift = ModifierKeys(rawValue: 1 << 0)

    /// Control key (either left or right)
    public static let control = ModifierKeys(rawValue: 1 << 1)

    /// Alt/Option key (either left or right)
    public static let alt = ModifierKeys(rawValue: 1 << 2)

    /// Command key (macOS) or Windows key (Windows)
    public static let command = ModifierKeys(rawValue: 1 << 3)
}

// MARK: - User Events

/// User-defined custom event.
///
/// UserEvent allows applications to post custom events to the event loop
/// from background threads or in response to external events (timers,
/// network callbacks, etc.). This provides a thread-safe way to communicate
/// with the main event loop.
///
/// Example:
/// ```swift
/// // Background thread posts user event
/// Task.detached {
///     let result = await performNetworkRequest()
///     await app.postUserEvent(UserEvent(NetworkResult(result)))
/// }
///
/// // Main thread receives event
/// if case .user(let userEvent) = event {
///     if let networkResult = userEvent.data as? NetworkResult {
///         print("Network request completed: \(networkResult)")
///     }
/// }
/// ```
public struct UserEvent: Sendable {
    /// Type-erased Sendable data payload
    private let _data: any Sendable

    /// The user-defined data payload.
    ///
    /// Cast this to your expected type when handling the event.
    public var data: Any {
        _data
    }

    /// Create a user event with Sendable data.
    ///
    /// The data must conform to Sendable to ensure thread safety when
    /// posting events from background threads.
    ///
    /// - Parameter data: The Sendable data payload
    public init<T: Sendable>(_ data: T) {
        self._data = data
    }
}
