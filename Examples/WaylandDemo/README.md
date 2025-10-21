# WaylandDemo

**⚠️ NOTE: This example is currently non-functional as Wayland support in Lumina is still under development.**

Demonstrates explicit Wayland backend selection on Linux.

## Purpose

This example shows how to force the Wayland backend instead of relying on automatic backend detection. Once Wayland support is complete, this will be useful for:

- **Testing**: Ensure your application works correctly with Wayland
- **Development**: Test Wayland-specific features without X11 fallback
- **Debugging**: Isolate Wayland-specific issues
- **Performance**: Leverage Wayland's native features (client-side decorations, better scaling, etc.)

## Requirements

### Build Requirements
- Linux operating system
- Swift 6.0 or later
- Wayland development libraries installed:
  - Debian/Ubuntu: `sudo apt install libwayland-dev libxkbcommon-dev`
  - Fedora/RHEL: `sudo dnf install wayland-devel libxkbcommon-devel`
- Lumina's main `Package.swift` must be configured to include Wayland support (see below)

### Runtime Requirements
- A running Wayland compositor (GNOME Wayland, KDE Plasma Wayland, Sway, etc.)
- `WAYLAND_DISPLAY` environment variable set (automatically set when running under Wayland)

## Setup

Before building this example, you need to enable Wayland support in Lumina's main `Package.swift`.

### 1. Enable CWaylandLinux dependency

Edit `/home/alexander/dev/Lumina/Package.swift` and uncomment line 34:

```swift
dependencies: [
    .product(name: "Logging", package: "swift-log"),
    .target(name: "CXCBLinux", condition: .when(platforms: [.linux])),
    .target(name: "CWaylandLinux", condition: .when(platforms: [.linux]))  // Uncomment this line
],
```

### 2. Build the example

You must build with the `LUMINA_WAYLAND` flag to enable Wayland support in the Lumina library:

### Option 1: Use the build script (recommended)
```bash
cd Examples/WaylandDemo
./build-wayland.sh
```

### Option 2: Manual build
```bash
cd Examples/WaylandDemo
swift build -Xswiftc -DLUMINA_WAYLAND
```

## Running

```bash
cd Examples/WaylandDemo
swift run -Xswiftc -DLUMINA_WAYLAND
```

Or if you used the build script, it will automatically run after building.

## Current Status

The Wayland backend in Lumina is **currently under development**. This example demonstrates the intended API for forcing Wayland backend selection:

```swift
#if LUMINA_WAYLAND
var app = try createLuminaApp(.wayland)  // Force Wayland - no X11 fallback
#endif
```

The example will compile and run with proper error handling when `LUMINA_WAYLAND` is not defined, but the Wayland implementation itself is not yet complete.

## Troubleshooting

### Build Errors

**Known Issue**: Building with `-Xswiftc -DLUMINA_WAYLAND` currently fails due to incomplete Wayland implementation in Lumina. This is expected and being actively worked on.

If you get "LUMINA_WAYLAND is not defined" when running without the flag:
- This is expected behavior - the example gracefully handles missing Wayland support
- The example will show instructions on how to enable Wayland when it's ready

### Runtime Errors

If you're running on X11 instead of Wayland, you'll get an error:
```
Error: Wayland backend requested but no Wayland display server detected
```

To check if you're running Wayland:
```bash
echo $WAYLAND_DISPLAY  # Should output something like "wayland-0"
echo $XDG_SESSION_TYPE  # Should output "wayland"
```

## Comparison with Auto-Detection

The standard `createLuminaApp()` (or `createLuminaApp(.auto)`) will:
1. Try Wayland first if `WAYLAND_DISPLAY` is set
2. Fall back to X11 if Wayland initialization fails
3. Work in both Wayland and X11 environments

This example uses `createLuminaApp(.wayland)` which:
1. Forces Wayland backend only
2. Fails immediately if Wayland is unavailable
3. Useful for testing/development scenarios

## Code Example

```swift
#if LUMINA_WAYLAND
// Force Wayland backend - no X11 fallback
var app = try createLuminaApp(.wayland)

var window = try app.createWindow(
    title: "Native Wayland Window",
    size: LogicalSize(width: 800, height: 600),
    resizable: true,
    monitor: nil
)

window.show()
try app.run()
#endif
```

## See Also

- **HelloWindow**: Basic example using auto-detection
- **InputExplorer**: Demonstrates input handling (works with both X11 and Wayland)
- **ScalingDemo**: Shows DPI scaling (Wayland has better fractional scaling support)
