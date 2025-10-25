# WaylandDemo

Demonstrates explicit Wayland backend selection on Linux.

## Purpose

This example shows how to force the Wayland backend instead of relying on automatic backend detection. This is useful for:

- **Testing**: Ensure your application works correctly with Wayland
- **Development**: Test Wayland-specific features without X11 fallback
- **Debugging**: Isolate Wayland-specific issues
- **Performance**: Leverage Wayland's native features (client-side decorations, better scaling, etc.)

## Requirements

### Build Requirements
- Linux operating system
- Swift 6.2 or later (6.1+ minimum for traits)
- Wayland development libraries installed:
  - Debian/Ubuntu: `sudo apt install libwayland-dev libxkbcommon-dev wayland-protocols`
  - Fedora/RHEL: `sudo dnf install wayland-devel wayland-protocols-devel libxkbcommon-devel`

### Runtime Requirements
- A running Wayland compositor (GNOME Wayland, KDE Plasma Wayland, Sway, etc.)
- `WAYLAND_DISPLAY` environment variable set (automatically set when running under Wayland)

## Setup

### Generate Wayland Protocol Bindings

The first time you build, Wayland protocol bindings need to be generated from XML files. This happens automatically when using the build script, or you can generate them manually:

```bash
# From the root Lumina directory
swift package plugin generate-wayland-protocols

# Or from any Example app directory
swift package --package-path ../.. plugin generate-wayland-protocols
```

### Build the example

Enable Wayland support using the `--traits Wayland` flag:

### Option 1: Use the build script (recommended)
```bash
cd Examples/WaylandDemo
./build-wayland.sh
```

The build script automatically checks for protocol files and generates them if needed.

### Option 2: Manual build
```bash
cd Examples/WaylandDemo
swift build --traits Wayland
```

Note: If protocol files don't exist, you'll need to generate them first (see above).

## Running

```bash
cd Examples/WaylandDemo
swift run --traits Wayland
```

Or if you used the build script, it will automatically run after building.

## Current Status

The Wayland backend is **fully functional**. This example demonstrates forcing Wayland backend selection:

```swift
#if LUMINA_WAYLAND
var platform = try createLuminaPlatform(.wayland)  // Force Wayland - no X11 fallback
var app = try platform.createApp()
#endif
```

The example will compile and run with proper error handling when `LUMINA_WAYLAND` is not defined.

### Wayland Feature Status

- ✅ Window creation and management
- ✅ Monitor enumeration and information
- ✅ Pointer events (enter/leave/move/click) with position tracking
- ✅ Extended button support (8 buttons: left/right/middle/button4-8)
- ✅ Modifier keys (Shift/Ctrl/Alt/Cmd) in button events
- ✅ Client-side decorations with full input handling
- ✅ Keyboard events with XKB support
- ✅ Window resize and move operations
- ⚠️ Cursor modes (normal mode only - hidden/disabled modes in progress)
- ⚠️ Raw input for FPS games (in progress)

## Troubleshooting

### Build Errors

If you get "LUMINA_WAYLAND is not defined" when running without the trait:
- This is expected behavior - the example gracefully handles missing Wayland support
- Build with `--traits Wayland` to enable Wayland backend

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

The standard `createLuminaPlatform()` (or `createLuminaPlatform(.auto)`) will:
1. Try Wayland first if `WAYLAND_DISPLAY` is set
2. Fall back to X11 if Wayland initialization fails
3. Work in both Wayland and X11 environments

This example uses `createLuminaPlatform(.wayland)` which:
1. Forces Wayland backend only
2. Fails immediately if Wayland is unavailable
3. Useful for testing/development scenarios

## Code Example

```swift
#if LUMINA_WAYLAND
// Force Wayland backend - no X11 fallback
var platform = try createLuminaPlatform(.wayland)
var app = try platform.createApp()

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
