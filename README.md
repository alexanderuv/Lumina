# Lumina

A modern, cross-platform windowing library for Swift, built from the ground up with Swift 6 concurrency in mind.

## Overview

Lumina provides a clean, type-safe API for creating windows and handling user input across macOS and Windows. It leverages Swift's latest features including strict concurrency, ownership annotations, and protocol-oriented design.

**Current Status**: Milestone 0 (Wave A) - Core Windowing & Input

### Features

- **Cross-platform**: macOS (AppKit) and Windows (Win32 API) backends
- **Modern Swift**: Built with Swift 6.2+, strict concurrency, and borrowing ownership model
- **Type-safe**: Explicit error handling with Result types
- **DPI-aware**: Automatic logical/physical coordinate conversion
- **Async-friendly**: Works seamlessly with Swift's async/await concurrency

## Platform Requirements

- **macOS**: macOS 15.0+ (Sequoia)
- **Windows**: Windows 11+ (planned)
- **Swift**: 6.0+
- **Xcode**: 16.0+ (for macOS development)

## Installation

### Swift Package Manager

Add Lumina to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/Lumina.git", from: "0.1.0")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["Lumina"]
)
```

## Quick Start

### Hello Window

The simplest Lumina application creates a window and runs the event loop:

```swift
import Lumina

@MainActor
func main() async throws {
    // Create application
    var app = try Application()

    // Create window
    let window = try Window.create(
        title: "Hello, Lumina!",
        size: LogicalSize(width: 800, height: 600)
    ).get()

    window.show()

    // Run event loop
    try app.run()
}

try await main()
```

### Window Management

Lumina provides comprehensive window control:

```swift
var window = try Window.create(
    title: "My App",
    size: LogicalSize(width: 1024, height: 768),
    resizable: true
).get()

// Show/hide window
window.show()
window.hide()

// Move and resize
window.moveTo(LogicalPosition(x: 100, y: 100))
window.resize(LogicalSize(width: 1280, height: 720))

// Set constraints
window.setMinSize(LogicalSize(width: 640, height: 480))
window.setMaxSize(LogicalSize(width: 1920, height: 1080))

// Focus
window.requestFocus()

// Query state
let size = window.size()
let position = window.position()
let scaleFactor = window.scaleFactor()

// Close (consumes window)
window.close()
```

### DPI and Scaling

Lumina automatically handles DPI scaling across different displays:

```swift
let window = try Window.create(
    title: "Scaling Demo",
    size: LogicalSize(width: 800, height: 600)
).get()

// Query scale factor
let scaleFactor = window.scaleFactor()  // 1.0 = normal, 2.0 = Retina

// Convert between logical and physical coordinates
let logicalSize = LogicalSize(width: 800, height: 600)
let physicalSize = logicalSize.toPhysical(scaleFactor: scaleFactor)

print("Logical: \(logicalSize.width) × \(logicalSize.height) points")
print("Physical: \(physicalSize.width) × \(physicalSize.height) pixels")
```

### Event Loop Modes

Lumina supports different event loop patterns:

#### Blocking Event Loop (Traditional)

```swift
var app = try Application()
let window = try Window.create(
    title: "App",
    size: LogicalSize(width: 800, height: 600)
).get()
window.show()

// Blocks until quit() is called
try app.run()
```

#### Non-blocking Poll (Game Loop)

```swift
var app = try Application()
let window = try Window.create(
    title: "Game",
    size: LogicalSize(width: 1920, height: 1080)
).get()
window.show()

// Custom game loop
while !shouldQuit {
    // Process all pending events
    _ = try app.poll()

    // Update game state
    updateGame(deltaTime)

    // Render frame
    renderFrame()
}
```

#### Low-power Wait

```swift
var app = try Application()
let window = try Window.create(
    title: "Editor",
    size: LogicalSize(width: 1024, height: 768)
).get()
window.show()

// Efficient idle loop
while !shouldQuit {
    try app.wait()      // Sleep until event arrives
    _ = try app.poll()  // Process the event
}
```

### Cursor Control

Change cursor appearance and visibility:

```swift
import Lumina

// Change cursor
Cursor.set(.hand)      // Pointing hand
Cursor.set(.ibeam)     // Text cursor
Cursor.set(.crosshair) // Crosshair
Cursor.set(.resizeNS)  // Vertical resize

// Hide/show cursor
Cursor.hide()
Cursor.show()

// Reset to default
Cursor.set(.arrow)
```

### Async/Await Integration

Lumina works seamlessly with Swift concurrency:

```swift
@MainActor
func main() async throws {
    var app = try Application()
    let window = try Window.create(
        title: "Async Demo",
        size: LogicalSize(width: 800, height: 600)
    ).get()
    window.show()

    // Background task can post user events
    Task.detached {
        let result = await performNetworkRequest()
        await app.postUserEvent(UserEvent(result))
    }

    // Event loop processes user events
    try app.run()
}
```

## Examples

The `Examples/` directory contains complete example applications:

- **HelloWindow**: Minimal window creation
- **InputExplorer**: Input event handling with async/await validation
- **ScalingDemo**: DPI scaling and coordinate conversion

Build and run examples:

```bash
cd Examples/HelloWindow
swift run

cd ../InputExplorer
swift run

cd ../ScalingDemo
swift run
```

## API Reference

### Core Types

- **`Application`**: Event loop and application lifecycle management
- **`Window`**: Window creation and manipulation
- **`Cursor`**: Cursor appearance and visibility control

### Geometry Types

- **`LogicalSize`** / **`PhysicalSize`**: Size in points vs pixels
- **`LogicalPosition`** / **`PhysicalPosition`**: Position in points vs pixels

### Event Types (Milestone 0 - Internal)

- **`Event`**: Window, pointer, keyboard, and user events
- **`WindowEvent`**: Created, closed, resized, moved, focused, scale changed
- **`PointerEvent`**: Moved, entered, left, button pressed/released, wheel
- **`KeyboardEvent`**: Key down/up, text input
- **`UserEvent`**: Custom application events

*Note: Event callback API will be added in a future milestone*

### Error Handling

- **`LuminaError`**: Typed error enum with cases:
  - `windowCreationFailed(reason:)`
  - `platformError(code:message:)`
  - `invalidState(_:)`
  - `eventLoopFailed(reason:)`

## Architecture

Lumina uses a layered architecture:

1. **Public API Layer** (`Lumina`): Cross-platform types and APIs
2. **Backend Layer**: Platform-specific implementations
   - macOS: AppKit/Cocoa (NSApplication, NSWindow)
   - Windows: Win32 API (CreateWindowEx, message loop)
3. **Foundation Layer**: Shared geometry, events, errors

All platform-specific code is conditionally compiled, resulting in zero overhead on each platform.

## Testing

Lumina uses Swift Testing framework:

```bash
# Run all tests
swift test

# Run with parallel execution
swift test --parallel

# Run specific test suite
swift test --filter GeometryTests
```

## Roadmap

### Milestone 0 (Current) - Wave A: Core Windowing & Input
- ✅ Window creation and management
- ✅ Basic event loop (run, poll, wait)
- ✅ DPI/scaling support
- ✅ Cursor control
- ⏳ Event callbacks (future enhancement)

### Future Milestones
- **Wave B**: Graphics integration (Metal/DirectX)
- **Wave C**: Advanced input (gamepad, touch)
- **Wave D**: Window features (menus, dialogs, file pickers)
- **Wave E**: Platform extensions (notifications, system tray)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Lumina is inspired by modern windowing libraries like winit (Rust) and GLFW, reimagined for Swift's unique capabilities.
