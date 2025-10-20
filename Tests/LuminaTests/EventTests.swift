import Testing
@testable import Lumina

/// Tests for event types (Event, WindowEvent, PointerEvent, KeyboardEvent, etc.)
///
/// Verifies:
/// - Event enum pattern matching
/// - Sendable conformance for thread safety
/// - ModifierKeys OptionSet operations
/// - KeyCode equality and hashing
/// - UserEvent creation and type erasure

@Suite("Event Types")
struct EventTests {

    // MARK: - Event Enum Tests

    @Suite("Event Enum")
    struct EventEnumTests {

        @Test("Create window event")
        func createWindowEvent() {
            let windowID = WindowID()
            let event = Event.window(.created(windowID))

            if case .window(let windowEvent) = event {
                if case .created(let id) = windowEvent {
                    #expect(id == windowID)
                } else {
                    Issue.record("Expected .created event")
                }
            } else {
                Issue.record("Expected .window event")
            }
        }

        @Test("Create pointer event")
        func createPointerEvent() {
            let windowID = WindowID()
            let position = LogicalPosition(x: 100, y: 200)
            let event = Event.pointer(.moved(windowID, position: position))

            if case .pointer(let pointerEvent) = event {
                if case .moved(let id, let pos) = pointerEvent {
                    #expect(id == windowID)
                    #expect(pos.x == 100)
                    #expect(pos.y == 200)
                } else {
                    Issue.record("Expected .moved event")
                }
            } else {
                Issue.record("Expected .pointer event")
            }
        }

        @Test("Create keyboard event")
        func createKeyboardEvent() {
            let windowID = WindowID()
            let keyCode = KeyCode.escape
            let modifiers: ModifierKeys = [.command, .shift]
            let event = Event.keyboard(.keyDown(windowID, key: keyCode, modifiers: modifiers))

            if case .keyboard(let keyboardEvent) = event {
                if case .keyDown(let id, let key, let mods) = keyboardEvent {
                    #expect(id == windowID)
                    #expect(key == keyCode)
                    #expect(mods == modifiers)
                } else {
                    Issue.record("Expected .keyDown event")
                }
            } else {
                Issue.record("Expected .keyboard event")
            }
        }

        @Test("Create user event")
        func createUserEvent() {
            let userData = "Test Data"
            let userEvent = UserEvent(userData)
            let event = Event.user(userEvent)

            if case .user(let evt) = event {
                if let data = evt.data as? String {
                    #expect(data == "Test Data")
                } else {
                    Issue.record("Expected String data")
                }
            } else {
                Issue.record("Expected .user event")
            }
        }
    }

    // MARK: - WindowEvent Tests

    @Suite("WindowEvent")
    struct WindowEventTests {

        @Test("Window created event")
        func windowCreated() {
            let windowID = WindowID()
            let event = WindowEvent.created(windowID)

            if case .created(let id) = event {
                #expect(id == windowID)
            } else {
                Issue.record("Expected .created event")
            }
        }

        @Test("Window resized event")
        func windowResized() {
            let windowID = WindowID()
            let size = LogicalSize(width: 800, height: 600)
            let event = WindowEvent.resized(windowID, size)

            if case .resized(let id, let sz) = event {
                #expect(id == windowID)
                #expect(sz.width == 800)
                #expect(sz.height == 600)
            } else {
                Issue.record("Expected .resized event")
            }
        }

        @Test("Window scale factor changed event")
        func scaleFactorChanged() {
            let windowID = WindowID()
            let event = WindowEvent.scaleFactorChanged(windowID, oldFactor: 1.0, newFactor: 2.0)

            if case .scaleFactorChanged(let id, let oldFactor, let newFactor) = event {
                #expect(id == windowID)
                #expect(oldFactor == 1.0)
                #expect(newFactor == 2.0)
            } else {
                Issue.record("Expected .scaleFactorChanged event")
            }
        }
    }

    // MARK: - PointerEvent Tests

    @Suite("PointerEvent")
    struct PointerEventTests {

        @Test("Pointer moved event")
        func pointerMoved() {
            let windowID = WindowID()
            let position = LogicalPosition(x: 50, y: 75)
            let event = PointerEvent.moved(windowID, position: position)

            if case .moved(let id, let pos) = event {
                #expect(id == windowID)
                #expect(pos.x == 50)
                #expect(pos.y == 75)
            } else {
                Issue.record("Expected .moved event")
            }
        }

        @Test("Button pressed event")
        func buttonPressed() {
            let windowID = WindowID()
            let position = LogicalPosition(x: 100, y: 200)
            let event = PointerEvent.buttonPressed(windowID, button: .left, position: position)

            if case .buttonPressed(let id, let button, let pos) = event {
                #expect(id == windowID)
                #expect(button == .left)
                #expect(pos.x == 100)
                #expect(pos.y == 200)
            } else {
                Issue.record("Expected .buttonPressed event")
            }
        }

        @Test("Button released event")
        func buttonReleased() {
            let windowID = WindowID()
            let position = LogicalPosition(x: 100, y: 200)
            let event = PointerEvent.buttonReleased(windowID, button: .right, position: position)

            if case .buttonReleased(let id, let button, let pos) = event {
                #expect(id == windowID)
                #expect(button == .right)
                #expect(pos.x == 100)
                #expect(pos.y == 200)
            } else {
                Issue.record("Expected .buttonReleased event")
            }
        }

        @Test("Mouse wheel event")
        func mouseWheel() {
            let windowID = WindowID()
            let event = PointerEvent.wheel(windowID, deltaX: 10.5, deltaY: -20.5)

            if case .wheel(let id, let deltaX, let deltaY) = event {
                #expect(id == windowID)
                #expect(deltaX == 10.5)
                #expect(deltaY == -20.5)
            } else {
                Issue.record("Expected .wheel event")
            }
        }
    }

    // MARK: - KeyboardEvent Tests

    @Suite("KeyboardEvent")
    struct KeyboardEventTests {

        @Test("Key down event")
        func keyDown() {
            let windowID = WindowID()
            let keyCode = KeyCode.return
            let modifiers: ModifierKeys = [.shift]
            let event = KeyboardEvent.keyDown(windowID, key: keyCode, modifiers: modifiers)

            if case .keyDown(let id, let key, let mods) = event {
                #expect(id == windowID)
                #expect(key == keyCode)
                #expect(mods.contains(.shift))
            } else {
                Issue.record("Expected .keyDown event")
            }
        }

        @Test("Key up event")
        func keyUp() {
            let windowID = WindowID()
            let keyCode = KeyCode.space
            let modifiers: ModifierKeys = []
            let event = KeyboardEvent.keyUp(windowID, key: keyCode, modifiers: modifiers)

            if case .keyUp(let id, let key, let mods) = event {
                #expect(id == windowID)
                #expect(key == keyCode)
                #expect(mods.isEmpty)
            } else {
                Issue.record("Expected .keyUp event")
            }
        }

        @Test("Text input event")
        func textInput() {
            let windowID = WindowID()
            let text = "Hello, 世界"
            let event = KeyboardEvent.textInput(windowID, text: text)

            if case .textInput(let id, let txt) = event {
                #expect(id == windowID)
                #expect(txt == "Hello, 世界")
            } else {
                Issue.record("Expected .textInput event")
            }
        }
    }

    // MARK: - KeyCode Tests

    @Suite("KeyCode")
    struct KeyCodeTests {

        @Test("Create key code from raw value")
        func createKeyCode() {
            let keyCode = KeyCode(rawValue: 0x35)
            #expect(keyCode.rawValue == 0x35)
        }

        @Test("Key code equality")
        func keyCodeEquality() {
            let key1 = KeyCode(rawValue: 0x35)
            let key2 = KeyCode(rawValue: 0x35)
            let key3 = KeyCode(rawValue: 0x24)

            #expect(key1 == key2)
            #expect(key1 != key3)
        }

        @Test("Common key codes")
        func commonKeyCodes() {
            #expect(KeyCode.escape.rawValue == 0x35)
            #expect(KeyCode.return.rawValue == 0x24)
            #expect(KeyCode.tab.rawValue == 0x30)
            #expect(KeyCode.space.rawValue == 0x31)
            #expect(KeyCode.backspace.rawValue == 0x33)
        }

        @Test("Key code hashing")
        func keyCodeHashing() {
            let key1 = KeyCode.escape
            let key2 = KeyCode.escape
            let key3 = KeyCode.return

            #expect(key1.hashValue == key2.hashValue)

            // Can be used in Set
            let keySet: Set<KeyCode> = [key1, key2, key3]
            #expect(keySet.count == 2)  // key1 and key2 are duplicates
        }
    }

    // MARK: - ModifierKeys Tests

    @Suite("ModifierKeys OptionSet")
    struct ModifierKeysTests {

        @Test("Create empty modifier set")
        func emptyModifiers() {
            let modifiers: ModifierKeys = []
            #expect(modifiers.isEmpty)
            #expect(!modifiers.contains(.shift))
        }

        @Test("Create single modifier")
        func singleModifier() {
            let modifiers: ModifierKeys = .shift
            #expect(!modifiers.isEmpty)
            #expect(modifiers.contains(.shift))
            #expect(!modifiers.contains(.control))
        }

        @Test("Create multiple modifiers")
        func multipleModifiers() {
            let modifiers: ModifierKeys = [.command, .shift]
            #expect(modifiers.contains(.command))
            #expect(modifiers.contains(.shift))
            #expect(!modifiers.contains(.control))
            #expect(!modifiers.contains(.alt))
        }

        @Test("Insert modifier")
        func insertModifier() {
            var modifiers: ModifierKeys = [.shift]
            modifiers.insert(.control)

            #expect(modifiers.contains(.shift))
            #expect(modifiers.contains(.control))
        }

        @Test("Remove modifier")
        func removeModifier() {
            var modifiers: ModifierKeys = [.shift, .control]
            modifiers.remove(.shift)

            #expect(!modifiers.contains(.shift))
            #expect(modifiers.contains(.control))
        }

        @Test("Union of modifier sets")
        func modifierUnion() {
            let mods1: ModifierKeys = [.shift, .control]
            let mods2: ModifierKeys = [.control, .alt]
            let union = mods1.union(mods2)

            #expect(union.contains(.shift))
            #expect(union.contains(.control))
            #expect(union.contains(.alt))
            #expect(!union.contains(.command))
        }

        @Test("Intersection of modifier sets")
        func modifierIntersection() {
            let mods1: ModifierKeys = [.shift, .control]
            let mods2: ModifierKeys = [.control, .alt]
            let intersection = mods1.intersection(mods2)

            #expect(!intersection.contains(.shift))
            #expect(intersection.contains(.control))
            #expect(!intersection.contains(.alt))
        }

        @Test("All modifiers")
        func allModifiers() {
            let modifiers: ModifierKeys = [.shift, .control, .alt, .command]

            #expect(modifiers.contains(.shift))
            #expect(modifiers.contains(.control))
            #expect(modifiers.contains(.alt))
            #expect(modifiers.contains(.command))
        }

        @Test("Modifier equality")
        func modifierEquality() {
            let mods1: ModifierKeys = [.shift, .command]
            let mods2: ModifierKeys = [.command, .shift]  // Order doesn't matter
            let mods3: ModifierKeys = [.shift]

            #expect(mods1 == mods2)
            #expect(mods1 != mods3)
        }
    }

    // MARK: - MouseButton Tests

    @Suite("MouseButton")
    struct MouseButtonTests {

        @Test("Mouse button types")
        func mouseButtonTypes() {
            let left = MouseButton.left
            let right = MouseButton.right
            let middle = MouseButton.middle

            #expect(left == .left)
            #expect(right == .right)
            #expect(middle == .middle)

            #expect(left != right)
            #expect(right != middle)
        }
    }

    // MARK: - UserEvent Tests

    @Suite("UserEvent")
    struct UserEventTests {

        @Test("Create user event with String")
        func createWithString() {
            let event = UserEvent("Test Message")

            if let data = event.data as? String {
                #expect(data == "Test Message")
            } else {
                Issue.record("Expected String data")
            }
        }

        @Test("Create user event with Int")
        func createWithInt() {
            let event = UserEvent(42)

            if let data = event.data as? Int {
                #expect(data == 42)
            } else {
                Issue.record("Expected Int data")
            }
        }

        @Test("Create user event with custom Sendable type")
        func createWithCustomType() {
            struct CustomData: Sendable {
                let id: Int
                let name: String
            }

            let customData = CustomData(id: 123, name: "Test")
            let event = UserEvent(customData)

            if let data = event.data as? CustomData {
                #expect(data.id == 123)
                #expect(data.name == "Test")
            } else {
                Issue.record("Expected CustomData")
            }
        }

        @Test("Type erasure preserves value")
        func typeErasure() {
            let original = [1, 2, 3, 4, 5]
            let event = UserEvent(original)

            if let data = event.data as? [Int] {
                #expect(data == original)
                #expect(data.count == 5)
            } else {
                Issue.record("Expected [Int] data")
            }
        }
    }
}
