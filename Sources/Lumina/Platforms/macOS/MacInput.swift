#if os(macOS)
import AppKit
import Foundation


/// NSEvent translation utilities for macOS.
///
/// These functions translate AppKit NSEvent objects to Lumina's cross-platform
/// Event types, handling coordinate conversion, modifier key mapping, and
/// key code normalization.

// MARK: - Event Translation

/// Translate an NSEvent to Lumina Events.
///
/// This is the main entry point for converting platform-specific events
/// to Lumina's unified event system.
///
/// - Parameters:
///   - nsEvent: The AppKit event to translate
///   - windowID: The WindowID associated with this event
/// - Returns: Array of Lumina Events (can be empty, one, or multiple events)
@MainActor
internal func translateNSEvent(_ nsEvent: NSEvent, for windowID: WindowID) -> [Event] {
    switch nsEvent.type {
    // Mouse events
    case .leftMouseDown:
        if let event = translateMouseDown(nsEvent, button: .left, windowID: windowID) {
            return [event]
        }
    case .leftMouseUp:
        if let event = translateMouseUp(nsEvent, button: .left, windowID: windowID) {
            return [event]
        }
    case .rightMouseDown:
        if let event = translateMouseDown(nsEvent, button: .right, windowID: windowID) {
            return [event]
        }
    case .rightMouseUp:
        if let event = translateMouseUp(nsEvent, button: .right, windowID: windowID) {
            return [event]
        }
    case .otherMouseDown:
        if let event = translateMouseDown(nsEvent, button: .middle, windowID: windowID) {
            return [event]
        }
    case .otherMouseUp:
        if let event = translateMouseUp(nsEvent, button: .middle, windowID: windowID) {
            return [event]
        }
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        if let event = translateMouseMoved(nsEvent, windowID: windowID) {
            return [event]
        }
    case .scrollWheel:
        if let event = translateScrollWheel(nsEvent, windowID: windowID) {
            return [event]
        }
    case .mouseEntered:
        guard let position = translateMousePosition(nsEvent) else {
            return []
        }
        return [.pointer(.entered(windowID, position: position))]
    case .mouseExited:
        guard let position = translateMousePosition(nsEvent) else {
            return []
        }
        return [.pointer(.left(windowID, position: position))]

    // Keyboard events
    case .keyDown:
        return translateKeyDown(nsEvent, windowID: windowID)
    case .keyUp:
        if let event = translateKeyUp(nsEvent, windowID: windowID) {
            return [event]
        }

    // Ignore other event types for now
    default:
        break
    }

    return []
}

// MARK: - Mouse Event Translation

@MainActor
private func translateMouseDown(
    _ nsEvent: NSEvent,
    button: MouseButton,
    windowID: WindowID
) -> Event? {
    guard let position = translateMousePosition(nsEvent) else {
        return nil
    }

    let modifiers = translateModifiers(nsEvent.modifierFlags)
    return .pointer(.buttonPressed(windowID, button: button, position: position, modifiers: modifiers))
}

@MainActor
private func translateMouseUp(
    _ nsEvent: NSEvent,
    button: MouseButton,
    windowID: WindowID
) -> Event? {
    guard let position = translateMousePosition(nsEvent) else {
        return nil
    }

    let modifiers = translateModifiers(nsEvent.modifierFlags)
    return .pointer(.buttonReleased(windowID, button: button, position: position, modifiers: modifiers))
}

@MainActor
private func translateMouseMoved(
    _ nsEvent: NSEvent,
    windowID: WindowID
) -> Event? {
    guard let position = translateMousePosition(nsEvent) else {
        return nil
    }

    return .pointer(.moved(windowID, position: position))
}

private func translateScrollWheel(
    _ nsEvent: NSEvent,
    windowID: WindowID
) -> Event? {
    let deltaX = Float(nsEvent.scrollingDeltaX)
    let deltaY = Float(nsEvent.scrollingDeltaY)

    // Only send event if there's actual scroll movement
    guard deltaX != 0 || deltaY != 0 else {
        return nil
    }

    return .pointer(.wheel(windowID, deltaX: deltaX, deltaY: deltaY))
}

/// Translate mouse position from NSEvent to logical coordinates.
///
/// AppKit uses bottom-left origin for window coordinates, but Lumina
/// uses top-left origin. This function handles the conversion.
@MainActor
private func translateMousePosition(_ nsEvent: NSEvent) -> LogicalPosition? {
    guard let window = nsEvent.window else {
        return nil
    }

    // Get mouse location in window coordinates (bottom-left origin)
    let locationInWindow = nsEvent.locationInWindow
    let windowFrame = window.frame

    // Convert to top-left origin (flip Y axis)
    let contentHeight = window.contentRect(forFrameRect: windowFrame).size.height
    let x = locationInWindow.x
    let y = contentHeight - locationInWindow.y

    return LogicalPosition(
        x: Float(x),
        y: Float(y)
    )
}

// MARK: - Keyboard Event Translation

private func translateKeyDown(
    _ nsEvent: NSEvent,
    windowID: WindowID
) -> [Event] {
    let keyCode = translateKeyCode(nsEvent)
    let modifiers = translateModifiers(nsEvent.modifierFlags)

    var events: [Event] = []

    // Always generate keyDown event for physical key press
    events.append(.keyboard(.keyDown(windowID, key: keyCode, modifiers: modifiers)))

    // Also generate textInput event if this key produces text
    if let textInputEvent = translateTextInput(nsEvent, windowID: windowID) {
        events.append(textInputEvent)
    }

    return events
}

private func translateKeyUp(
    _ nsEvent: NSEvent,
    windowID: WindowID
) -> Event? {
    let keyCode = translateKeyCode(nsEvent)
    let modifiers = translateModifiers(nsEvent.modifierFlags)

    return .keyboard(.keyUp(windowID, key: keyCode, modifiers: modifiers))
}

/// Translate NSEvent key code to Lumina KeyCode.
///
/// macOS key codes are already scan codes (hardware key positions),
/// so we can use them directly.
private func translateKeyCode(_ nsEvent: NSEvent) -> KeyCode {
    KeyCode(rawValue: UInt32(nsEvent.keyCode))
}

/// Translate NSEvent modifier flags to Lumina ModifierKeys.
private func translateModifiers(_ flags: NSEvent.ModifierFlags) -> ModifierKeys {
    var modifiers: ModifierKeys = []

    if flags.contains(.shift) {
        modifiers.insert(.shift)
    }
    if flags.contains(.control) {
        modifiers.insert(.control)
    }
    if flags.contains(.option) {
        modifiers.insert(.alt)
    }
    if flags.contains(.command) {
        modifiers.insert(.command)
    }

    return modifiers
}

// MARK: - Text Input Translation

/// Translate keyboard event to text input event.
///
/// This extracts the character representation of a key press, accounting
/// for keyboard layout and dead keys.
internal func translateTextInput(_ nsEvent: NSEvent, windowID: WindowID) -> Event? {
    guard let characters = nsEvent.characters, !characters.isEmpty else {
        return nil
    }

    // Filter out control characters and modifiers
    let filteredText = characters.filter { char in
        !char.isNewline && !char.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || (scalar.value >= 0x7F && scalar.value < 0xA0)
        }
    }

    guard !filteredText.isEmpty else {
        return nil
    }

    return .keyboard(.textInput(windowID, text: filteredText))
}

#endif
