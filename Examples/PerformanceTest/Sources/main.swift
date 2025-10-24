import Lumina
import Foundation

/// Performance verification for Lumina
///
/// This test verifies that window creation meets the performance requirement
/// of < 100ms as specified in the tasks.

@MainActor
func measureWindowCreation() throws {
    // Initialize platform first, then create app
    var platform = try createLuminaPlatform()
    var app = try platform.createApp()

    print("=== Lumina Performance Test ===")
    print("Requirement: Window creation < 100ms")
    print("")

    // Measure window creation time
    let start = Date()
    let window = try app.createWindow(
        title: "Performance Test",
        size: LogicalSize(width: 800, height: 600),
        resizable: true,
        monitor: nil
    )
    let elapsed = Date().timeIntervalSince(start) * 1000 // in ms

    print("Window creation time: \(String(format: "%.2f", elapsed)) ms")

    if elapsed < 100 {
        print("✓ Performance requirement MET (< 100ms)")
    } else {
        print("✗ Performance requirement NOT MET (>= 100ms)")
    }
    print("")

    // Test multiple window creations
    print("Testing 10 consecutive window creations:")
    var times: [Double] = []

    for i in 1...10 {
        let start = Date()
        var testWindow = try app.createWindow(
            title: "Test \(i)",
            size: LogicalSize(width: 400, height: 300),
            resizable: true,
            monitor: nil
        )
        let elapsed = Date().timeIntervalSince(start) * 1000
        times.append(elapsed)
        print("  Window \(i): \(String(format: "%.2f", elapsed)) ms")
        testWindow.close()
    }

    let average = times.reduce(0, +) / Double(times.count)
    let max = times.max() ?? 0
    let min = times.min() ?? 0

    print("")
    print("Statistics:")
    print("  Average: \(String(format: "%.2f", average)) ms")
    print("  Minimum: \(String(format: "%.2f", min)) ms")
    print("  Maximum: \(String(format: "%.2f", max)) ms")
    print("")

    if average < 100 {
        print("✓ Average window creation meets requirement")
    } else {
        print("✗ Average window creation exceeds requirement")
    }

    window.close()
    print("")
    print("=== Performance Test Complete ===")
}

try measureWindowCreation()
