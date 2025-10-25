#if os(macOS)
import AppKit
import Foundation


/// NSEvent translation utilities for macOS.
///
/// These functions translate AppKit NSEvent objects to Lumina's cross-platform
/// Event types, handling coordinate conversion, modifier key mapping, and
/// key code normalization.

// MARK: - Event Translation

/// Translate an NSEvent to a Lumina Event.
///
/// This is the main entry point for converting platform-specific events
/// to Lumina's unified event system.
///
/// - Parameters:
///   - nsEvent: The AppKit event to translate
///   - windowID: The WindowID associated with this event
/// - Returns: Lumina Event, or nil if the event should be ignored
@MainActor
internal func translateNSEvent(_ nsEvent: NSEvent, for windowID: WindowID) -> Event? {
    switch nsEvent.type {
    // Mouse events
    case .leftMouseDown:
        return translateMouseDown(nsEvent, button: .left, windowID: windowID)
    case .leftMouseUp:
        return translateMouseUp(nsEvent, button: .left, windowID: windowID)
    case .rightMouseDown:
        return translateMouseDown(nsEvent, button: .right, windowID: windowID)
    case .rightMouseUp:
        return translateMouseUp(nsEvent, button: .right, windowID: windowID)
    case .otherMouseDown:
        return translateMouseDown(nsEvent, button: .middle, windowID: windowID)
    case .otherMouseUp:
        return translateMouseUp(nsEvent, button: .middle, windowID: windowID)
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        return translateMouseMoved(nsEvent, windowID: windowID)
    case .scrollWheel:
        return translateScrollWheel(nsEvent, windowID: windowID)
    case .mouseEntered:
        guard let position = translateMousePosition(nsEvent) else {
            return nil
        }
        return .pointer(.entered(windowID, position: position))
    case .mouseExited:
        guard let position = translateMousePosition(nsEvent) else {
            return nil
        }
        return .pointer(.left(windowID, position: position))

    // Keyboard events
    case .keyDown:
        return translateKeyDown(nsEvent, windowID: windowID)
    case .keyUp:
        return translateKeyUp(nsEvent, windowID: windowID)

    // Ignore other event types for now
    default:
        return nil
    }
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
) -> Event? {
    let keyCode = translateKeyCode(nsEvent)
    let modifiers = translateModifiers(nsEvent.modifierFlags)

    return .keyboard(.keyDown(windowID, key: keyCode, modifiers: modifiers))
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
