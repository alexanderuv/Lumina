# Lumina

A modern, cross-platform windowing library for Swift, built from the ground up with Swift 6 concurrency in mind.

## Overview

Lumina provides a clean, type-safe API for creating windows and handling user input across macOS, Linux, and Windows. It leverages Swift's latest features including strict concurrency, ownership annotations, and protocol-oriented design.

**Current Status**: Milestone 1 - Linux Support & macOS Wave B

### Features

- **Cross-platform**: macOS (AppKit), Linux (X11 + Wayland), and Windows (Win32 API) backends
- **Modern Swift**: Built with Swift 6.2+, strict concurrency, and borrowing ownership model
- **Type-safe**: Explicit error handling with typed error enums
- **DPI-aware**: Automatic logical/physical coordinate conversion with mixed-DPI support
- **Async-friendly**: Works seamlessly with Swift's async/await concurrency
- **Flexible event loops**: Wait, poll, and timeout modes for different application patterns
- **Logging**: Structured logging via swift-log integration
- **Clipboard**: Text clipboard operations (macOS, Linux X11, Linux Wayland)
- **Monitor enumeration**: Query connected displays and their configurations

## Platform Requirements

- **macOS**: macOS 15.0+ (Sequoia)
- **Linux**: Ubuntu 24.04+ / Fedora 40+ / Arch Linux (with X11 or Wayland)
- **Windows**: Windows 11+ (Milestone 0 support)
- **Swift**: 6.2+ (6.1+ for traits, 6.2+ recommended)
- **Xcode**: 16.2+ (for macOS development)

## Installation

### Swift Package Manager

Add Lumina to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/Lumina.git", from: "0.2.0")
]
```

Then add it to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["Lumina"]
)
```

### Linux Dependencies

Lumina requires system libraries for Linux X11 and Wayland support.

#### Ubuntu / Debian

```bash
# X11 backend (required)
sudo apt install libxcb1-dev libxcb-keysyms1-dev libxcb-xkb-dev \
                 libxcb-xinput-dev libxcb-randr0-dev \
                 libxkbcommon-dev libxkbcommon-x11-dev

# Wayland backend (optional - only if you need Wayland support)
sudo apt install libwayland-dev libxkbcommon-dev
```

#### Fedora / RHEL

```bash
# X11 backend
sudo dnf install libxcb-devel xcb-util-keysyms-devel \
                 libxkbcommon-devel libxkbcommon-x11-devel

# Wayland backend
sudo dnf install wayland-devel libxkbcommon-devel
```

#### Arch Linux

```bash
# X11 backend
sudo pacman -S libxcb libxkbcommon

# Wayland backend
sudo pacman -S wayland libxkbcommon
```

### Building on Linux

```bash
# Clone the repository
git clone https://github.com/yourusername/Lumina.git
cd Lumina

# Build with X11 support only (default)
swift build

# Build with Wayland support (requires Wayland dependencies installed)
swift build --traits Wayland

# View trait information
swift package dump-package | grep -A 5 "traits"

# Run tests
swift test

# Build in release mode
swift build -c release
```

**Wayland Support:**
- By default, Lumina builds with **X11 support only** to avoid build errors if Wayland libraries are not installed
- To enable Wayland support, you must:
  1. Install Wayland development libraries (see dependencies above)
  2. Build with the Wayland trait: `swift build --traits Wayland`

**Backend Selection:**
The Linux backend is automatically selected at runtime based on your session:
- **X11**: Used when running in an X11 session (`$DISPLAY` is set)
- **Wayland**: Used when running in a Wayland session (`$WAYLAND_DISPLAY` is set) - *only if compiled with Wayland support*
- If Wayland support is compiled in and both environment variables are set, Wayland is preferred with X11 as fallback

## Quick Start

### Hello Window

The simplest Lumina application creates a window and runs the event loop:

```swift
import Lumina

@MainActor
func main() async throws {
    // Create application
    var app = try createLuminaApp()

    // Create window
    let window = try app.createWindow(
        title: "Hello, Lumina!",
        size: LogicalSize(width: 800, height: 600),
        resizable: true,
        monitor: nil
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
var app = try createLuminaApp()
var window = try app.createWindow(
    title: "My App",
    size: LogicalSize(width: 1024, height: 768),
    resizable: true,
    monitor: nil
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
var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Scaling Demo",
    size: LogicalSize(width: 800, height: 600),
    resizable: true,
    monitor: nil
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
var app = try createLuminaApp()
let window = try app.createWindow(
    title: "App",
    size: LogicalSize(width: 800, height: 600),
    resizable: true,
    monitor: nil
).get()
window.show()

// Blocks until quit() is called
try app.run()
```

#### Non-blocking Poll (Game Loop)

```swift
var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Game",
    size: LogicalSize(width: 1920, height: 1080),
    resizable: true,
    monitor: nil
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
var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Editor",
    size: LogicalSize(width: 1024, height: 768),
    resizable: true,
    monitor: nil
).get()
window.show()

// Efficient idle loop
while !shouldQuit {
    try app.wait()      // Sleep until event arrives
    _ = try app.poll()  // Process the event
}
```

### Cursor Control

Change cursor appearance and visibility (Milestone 1 API):

```swift
import Lumina

var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Cursor Demo",
    size: LogicalSize(width: 800, height: 600),
    resizable: true,
    monitor: nil
).get()

// Get cursor for this window
let cursor = window.cursor()

// Change cursor
cursor.set(.hand)      // Pointing hand
cursor.set(.ibeam)     // Text cursor
cursor.set(.crosshair) // Crosshair
cursor.set(.resizeNS)  // Vertical resize

// Hide/show cursor
cursor.hide()
cursor.show()

// Reset to default
cursor.set(.arrow)
```

### Clipboard Operations

Read and write text to the system clipboard (Milestone 1):

```swift
import Lumina

// Write text to clipboard
try Clipboard.writeText("Hello from Lumina!")

// Read text from clipboard
if let text = try Clipboard.readText() {
    print("Clipboard contains: \(text)")
}

// Check if clipboard has changed (macOS only)
if Clipboard.hasChanged() {
    print("Clipboard was modified")
}

// Query clipboard capabilities
let caps = Clipboard.capabilities()
if caps.supportsText {
    print("Text clipboard supported on this platform")
}
```

### Monitor Enumeration

Query connected displays and their properties (Milestone 1):

```swift
import Lumina

// Enumerate all monitors
let monitors = try enumerateMonitors()

for monitor in monitors {
    print("Monitor \(monitor.id):")
    print("  Name: \(monitor.name)")
    print("  Position: \(monitor.position.x), \(monitor.position.y)")
    print("  Size: \(monitor.size.width) × \(monitor.size.height)")
    print("  Scale: \(monitor.scaleFactor)x")
    print("  Primary: \(monitor.isPrimary)")
    print("  Work area: \(monitor.workArea)")
}

// Get primary monitor
let primary = try primaryMonitor()
print("Primary monitor: \(primary.name)")

// Get window's current monitor
var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Monitor Demo",
    size: LogicalSize(width: 800, height: 600),
    resizable: true,
    monitor: nil
).get()
let currentMonitor = try window.currentMonitor()
print("Window is on: \(currentMonitor.name)")
```

### Advanced Window Features (Milestone 1)

Control window decorations, transparency, and stacking:

```swift
import Lumina

var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Advanced Window",
    size: LogicalSize(width: 800, height: 600),
    resizable: true,
    monitor: nil
).get()

// Request redraw (macOS Wave B)
window.requestRedraw()  // Triggers RedrawEvent

// Toggle window decorations (macOS, X11)
try window.setDecorated(false)  // Borderless window
try window.setDecorated(true)   // Restore borders

// Always-on-top (macOS, X11)
try window.setAlwaysOnTop(true)  // Floating window
try window.setAlwaysOnTop(false) // Normal stacking

// Transparency (macOS, Wayland)
try window.setTransparent(true)  // Enable transparency
try window.setTransparent(false) // Disable transparency

// Query window capabilities
let caps = window.capabilities()
if caps.supportsTransparency {
    try window.setTransparent(true)
}
if caps.supportsAlwaysOnTop {
    try window.setAlwaysOnTop(true)
}
```

### Control Flow Modes (Milestone 1)

Fine-grained control over the event loop:

```swift
import Lumina

var app = try createLuminaApp()
let window = try app.createWindow(
    title: "Control Flow Demo",
    size: LogicalSize(width: 800, height: 600)
)
window.show()

// Wait mode: Block until next event
while let event = app.pumpEvents(mode: .wait) {
    handleEvent(event)
}

// Poll mode: Process all pending events, return immediately
while let event = app.pumpEvents(mode: .poll) {
    handleEvent(event)
}

// WaitUntil mode: Block with timeout
let deadline = Deadline(seconds: 0.016)  // 60 FPS target
while let event = app.pumpEvents(mode: .waitUntil(deadline)) {
    handleEvent(event)
}
```

### Async/Await Integration

Lumina works seamlessly with Swift concurrency:

```swift
@MainActor
func main() async throws {
    var app = try createLuminaApp()
    let window = try app.createWindow(
        title: "Async Demo",
        size: LogicalSize(width: 800, height: 600),
        resizable: true,
        monitor: nil
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

## Platform Compatibility

For detailed platform feature support and known limitations, see [Platform Compatibility Matrix](docs/platform-compatibility.md).

## Roadmap

### Milestone 0 (Complete) - Wave A: Core Windowing & Input
- ✅ Window creation and management
- ✅ Basic event loop (run, poll, wait)
- ✅ DPI/scaling support
- ✅ Cursor control (macOS, Windows)

### Milestone 1 (Complete) - Linux Support & macOS Wave B
- ✅ Linux X11 backend (full Wave A support)
- ✅ Linux Wayland backend (full Wave A support)
- ✅ Extended event loop modes (wait, poll, waitUntil with timeout)
- ✅ Redraw events and frame pacing
- ✅ Window decorations toggle (macOS, X11)
- ✅ Always-on-top windows (macOS, X11)
- ✅ Window transparency (macOS, Wayland)
- ✅ Clipboard text operations (all platforms)
- ✅ Monitor enumeration and configuration changes
- ✅ Structured logging (swift-log integration)
- ✅ Runtime capability detection

### Future Milestones
- **Milestone 2**: Fullscreen mode, IME support, custom cursors, drag-and-drop
- **Milestone 3**: Graphics integration (Metal/Vulkan/DirectX)
- **Milestone 4**: Advanced input (touch, gamepad)
- **Milestone 5**: Window features (menus, dialogs, file pickers)
- **Milestone 6**: Platform extensions (notifications, system tray)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Lumina is inspired by modern windowing libraries like winit (Rust) and GLFW, reimagined for Swift's unique capabilities.
