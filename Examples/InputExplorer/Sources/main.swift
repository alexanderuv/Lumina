import Lumina
import Foundation

/// InputExplorer - Demonstrates async/await works with event loop
///
/// NOTE: Milestone 0 doesn't have event callbacks yet.
/// This example shows that async tasks work alongside the event loop,
/// and demonstrates the event types that will be used in future milestones.

@main
struct InputExplorer: LuminaApp {
    func configure() async throws {
        var window = try Window.create(
            title: "Input Explorer - Event Types Demo",
            size: LogicalSize(width: 600, height: 400)
        ).get()

        window.show()

        print("=== Input Explorer - Event Types ===\n")
        print("Milestone 0: Event loop + async/await demonstration")
        print("(Event handling callbacks will be added in a future milestone)\n")

        // Demonstrate the event types that exist (even though we can't process them yet)
        print("Available Event Types:")
        demonstrateEventTypes()

        print("\n✓ Event loop is running")
        print("✓ Async tasks work concurrently")
        print("✓ Window interaction works (try resizing, moving)")
        print("\nClose window or press Cmd+Q to exit.")

        // Spawn async task to demonstrate async/await works with event loop
        _ = Task {
            for i in 1...3 {
                try? await Task.sleep(for: .seconds(2))
                print("[\(Date())] Async task \(i) - event loop still responsive!")
            }
        }
    }
}

/// Demonstrate the event types defined in Milestone 0
func demonstrateEventTypes() {
    // Window events
    print("  Window: .resized, .moved, .closed, .focusGained, .focusLost, .scaleFactorChanged")

    // Pointer events
    print("  Pointer: .moved, .buttonPressed, .buttonReleased, .scrolled")

    // Keyboard events
    print("  Keyboard: .keyPressed, .keyReleased, .textInput")

    // User events
    print("  User: .user (custom events from background threads)")
}
