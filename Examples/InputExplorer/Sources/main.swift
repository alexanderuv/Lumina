import Lumina
import Foundation

/// InputExplorer - Demonstrates event handling in Milestone 0
///
/// This example shows all the event types supported in M0:
/// - Window events (closed, resized, moved, focus, scale factor)
/// - Pointer events (motion, button press/release, scroll, enter/leave)
/// - Keyboard events (key down/up, modifiers, text input)
/// - User events (custom events from background threads)

@main
struct InputExplorer {
    static func main() throws {
        // Initialize platform first, then create app
        let platform = try createLuminaPlatform()
        var app = try platform.createApp()

        var window = try app.createWindow(
            title: "Input Explorer - All M0 Events",
            size: LogicalSize(width: 600, height: 400),
            resizable: true,
            monitor: nil as Monitor?
        )

        window.show()

        print("=== Input Explorer - Milestone 0 Events ===\n")
        print("This example demonstrates ALL events supported in M0:")
        print("  • Window: close, resize, move, focus, scale factor")
        print("  • Pointer: motion, buttons, scroll, enter/leave")
        print("  • Keyboard: key down/up, modifiers, text input")
        print("  • User: custom background thread events")
        print("\nTry interacting with the window!")
        print("Close window or press Cmd+Q to exit.\n")

        // Custom event loop
        var running = true
        var eventCount = 0

        while running {
            // Poll for events
            while let event = try app.poll() {
                eventCount += 1

                switch event {
                // Window Events
                case .window(let windowEvent):
                    switch windowEvent {
                    case .closed(let id):
                        print("[\(eventCount)] Window closed: \(id)")
                        running = false

                    case .resized(let id, let size):
                        print("[\(eventCount)] Window resized: \(id) -> \(size.width)x\(size.height)")

                    case .moved(let id, let pos):
                        print("[\(eventCount)] Window moved: \(id) -> (\(pos.x), \(pos.y))")

                    case .focused(let id):
                        print("[\(eventCount)] Window gained focus: \(id)")

                    case .unfocused(let id):
                        print("[\(eventCount)] Window lost focus: \(id)")

                    case .scaleFactorChanged(let id, let oldFactor, let newFactor):
                        print("[\(eventCount)] Scale factor changed: \(id) -> \(oldFactor)x to \(newFactor)x")

                    case .created(_):
                        break  // Don't print window created events
                    }

                // Pointer Events
                case .pointer(let pointerEvent):
                    switch pointerEvent {
                    case .moved(let id, let pos):
                        // Only print every 60th move event to avoid spam
                       // if eventCount % 60 == 0 {
                            print("[\(eventCount)] Pointer moved: \(id) -> (\(pos.x), \(pos.y))")
                       // }

                    case .buttonPressed(let id, let button, let pos, let mods):
                        let modStr = formatModifiers(mods)
                        print("[\(eventCount)] Button pressed: \(id) \(button) at (\(pos.x), \(pos.y)) mods=\(modStr)")

                    case .buttonReleased(let id, let button, let pos, let mods):
                        let modStr = formatModifiers(mods)
                        print("[\(eventCount)] Button released: \(id) \(button) at (\(pos.x), \(pos.y)) mods=\(modStr)")

                    case .wheel(let id, let dx, let dy):
                        print("[\(eventCount)] Scroll: \(id) -> dx=\(dx), dy=\(dy)")

                    case .entered(let id, let pos):
                        print("[\(eventCount)] Pointer entered window: \(id) at (\(pos.x), \(pos.y))")

                    case .left(let id, let pos):
                        print("[\(eventCount)] Pointer left window: \(id) at (\(pos.x), \(pos.y))")
                    }

                // Keyboard Events
                case .keyboard(let keyboardEvent):
                    switch keyboardEvent {
                    case .keyDown(let id, let key, let mods):
                        let modStr = formatModifiers(mods)
                        print("[\(eventCount)] Key down: \(id) key=\(key.rawValue) mods=\(modStr)")

                    case .keyUp(let id, let key, let mods):
                        let modStr = formatModifiers(mods)
                        print("[\(eventCount)] Key up: \(id) key=\(key.rawValue) mods=\(modStr)")

                    case .textInput(let id, let text):
                        print("[\(eventCount)] Text input: \(id) -> \"\(text)\"")
                    }

                // User Events
                case .user(let userEvent):
                    print("[\(eventCount)] User event: \(userEvent.data)")

                // M1 Events (not actively demonstrated in this example)
                case .redraw:
                    print("[\(eventCount)] Redraw event")
                    break
                case .monitor:
                    print("[\(eventCount)] Monitor event")
                    break
                }
            }

            if !running {
                break
            }

            // Wait for next event (low-power sleep)
            try app.wait()
        }

        // Keep window alive
        _ = window

        print("\n✓ Total events processed: \(eventCount)")
        print("✓ Event loop demonstration complete!")
    }

    static func formatModifiers(_ mods: ModifierKeys) -> String {
        var parts: [String] = []
        if mods.contains(.shift) { parts.append("Shift") }
        if mods.contains(.control) { parts.append("Ctrl") }
        if mods.contains(.alt) { parts.append("Alt") }
        if mods.contains(.command) { parts.append("Cmd") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}
