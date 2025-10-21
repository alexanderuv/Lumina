# Lumina Wayland Implementation - libdecor Architecture

**Clean rewrite following SDL3/GLFW best practices**

---

## Architecture Overview

```
Application Lifecycle:
┌──────────────────────────────────────────────────────────────┐
│ WaylandApplication                                            │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Display & libdecor Context                               │ │
│ │ - wl_display (Wayland connection)                        │ │
│ │ - libdecor (decoration manager)                          │ │
│ │ - wl_seat (input devices)                                │ │
│ └──────────────────────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Event Loop                                               │ │
│ │ 1. libdecor_dispatch() - process decoration events       │ │
│ │ 2. wl_display_dispatch_pending() - process Wayland       │ │
│ │ 3. Input event translation                               │ │
│ │ 4. Event queue management                                │ │
│ └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

Window Lifecycle:
┌──────────────────────────────────────────────────────────────┐
│ WaylandWindow                                                 │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ libdecor_frame (replaces raw xdg-toplevel)              │ │
│ │ - Automatic SSD/CSD selection                            │ │
│ │ - Theme integration                                      │ │
│ │ - Configure event handling                               │ │
│ │ - Decoration button events                               │ │
│ └──────────────────────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Content Surface                                          │ │
│ │ - wl_surface (Wayland surface)                           │ │
│ │ - wl_buffer (shared memory buffer)                       │ │
│ └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Key Principles

### 1. **libdecor is the Primary Decoration Path**
- SDL3/GLFW use libdecor as PRIMARY, not fallback
- libdecor automatically chooses SSD or CSD based on compositor
- No manual xdg-decoration protocol handling needed

### 2. **Event Loop Integration**
Following SDL3 pattern:
```c
// Each frame:
libdecor_dispatch(decorContext, 0);           // Non-blocking libdecor events
wl_display_dispatch_pending(display);         // Wayland protocol events
process_input_events();                        // Input translation
wl_display_flush(display);                    // Flush requests
```

### 3. **Proper Resource Lifecycle**
- libdecor owns window decorations
- Application owns display/libdecor context
- Windows store libdecor_frame, not raw xdg objects

### 4. **Error Handling**
- Check all C API return values
- Graceful degradation (e.g., keyboard without XKB)
- Proper cleanup on all error paths

---

## File Structure

```
Sources/Lumina/Platforms/Linux/Wayland/
├── WaylandApplication.swift     # Main application, event loop
├── WaylandWindow.swift          # Window using libdecor_frame
├── WaylandInput.swift           # Input event translation
└── WaylandTypes.swift           # Helper types, utilities
```

---

## Implementation Details

### WaylandApplication

**Responsibilities:**
- Wayland display connection
- libdecor context management
- Event loop (libdecor + Wayland + input)
- Window registry
- Input device management

**Key State:**
```swift
@MainActor
struct WaylandApplication: LuminaApp {
    private let display: OpaquePointer        // wl_display*
    private let decorContext: OpaquePointer   // libdecor*
    private let seat: OpaquePointer?          // wl_seat*

    private let xkbContext: OpaquePointer?    // xkb_context*
    private var pointer: OpaquePointer?       // wl_pointer*
    private var keyboard: OpaquePointer?      // wl_keyboard*
    private var xkbState: OpaquePointer?      // xkb_state*

    private var eventQueue: [Event] = []
    private var windows: [WindowID: WaylandWindow] = [:]
    private var shouldQuit = false
}
```

**Event Loop Pattern (following SDL3):**
```swift
mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
    // 1. Process libdecor events (decoration configure, close, etc.)
    libdecor_dispatch(decorContext, 0)

    // 2. Process Wayland protocol events
    switch mode {
    case .poll:
        wl_display_dispatch_pending(display)
    case .wait:
        wl_display_dispatch(display)
    case .waitUntil(let deadline):
        // select() with timeout on wl_display_get_fd()
    }

    // 3. Flush outgoing requests
    wl_display_flush(display)

    // 4. Return queued event
    return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
}
```

---

### WaylandWindow

**Responsibilities:**
- libdecor_frame lifecycle
- Content surface management
- Buffer allocation/attachment
- Window properties (title, size, etc.)

**Key State:**
```swift
@MainActor
struct WaylandWindow: LuminaWindow {
    let id: WindowID

    private let frame: OpaquePointer         // libdecor_frame*
    private let surface: OpaquePointer       // wl_surface*
    private let buffer: OpaquePointer?       // wl_buffer*

    private var currentSize: LogicalSize
    private var isVisible: Bool = false
}
```

**Creation Pattern (following SDL3/GLFW):**
```swift
static func create(...) throws -> WaylandWindow {
    // 1. Create Wayland surface
    let surface = wl_compositor_create_surface(compositor)

    // 2. Create libdecor frame (replaces xdg-surface + xdg-toplevel + xdg-decoration)
    var interface = libdecor_frame_interface(
        configure: { frame, config, userData in
            // libdecor provides configured size and state
            // Resize buffer, commit surface
        },
        close: { frame, userData in
            // User clicked close button
        },
        commit: { frame, userData in
            // Ready to commit
        }
    )

    let frame = libdecor_decorate(
        decorContext,
        surface,
        &interface,
        userData
    )

    // 3. Set properties
    libdecor_frame_set_title(frame, title)
    libdecor_frame_set_app_id(frame, "com.lumina.app")

    // 4. Map frame (make visible)
    libdecor_frame_map(frame)

    return WaylandWindow(frame: frame, surface: surface, ...)
}
```

**Benefits of libdecor_frame:**
- ✓ Automatic SSD/CSD selection
- ✓ No manual xdg_surface/xdg_toplevel listeners
- ✓ Configure events handled by libdecor
- ✓ Decoration buttons work automatically

---

### WaylandInput

**Responsibilities:**
- wl_pointer → PointerEvent translation
- wl_keyboard + XKB → KeyboardEvent translation
- Seat capability detection
- Surface focus tracking

**Input Flow:**
```
wl_seat (capabilities callback)
    ↓
wl_pointer / wl_keyboard interfaces created
    ↓
Listener callbacks (C function pointers)
    ↓
Swift event translation
    ↓
Event queue in WaylandApplication
    ↓
pumpEvents() returns to user
```

**XKB Integration:**
```swift
// Keyboard listener keymap callback:
keymap: { data, keyboard, format, fd, size in
    // 1. mmap the keymap file
    let map = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)

    // 2. Create XKB keymap
    let keymap = xkb_keymap_new_from_string(
        xkbContext,
        map,
        XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS
    )

    // 3. Create XKB state for modifier tracking
    let state = xkb_state_new(keymap)

    // Store for use in key events
}
```

---

## Robustness Features

### 1. **Error Recovery**
```swift
// Display connection error
if wl_display_get_error(display) != 0 {
    let error = wl_display_get_protocol_error(display, &interface, &id)
    logger.error("Wayland protocol error: \(error) on \(interface):\(id)")
    // Attempt reconnect or graceful shutdown
}
```

### 2. **Resource Cleanup**
```swift
// Proper cleanup order (reverse of creation):
consuming func close() {
    if let buffer = buffer {
        wl_buffer_destroy(buffer)
    }
    libdecor_frame_unref(frame)
    wl_surface_destroy(surface)
}

// Application cleanup:
deinit {
    if let keyboard = keyboard {
        wl_keyboard_release(keyboard)
    }
    if let pointer = pointer {
        wl_pointer_release(pointer)
    }
    if let seat = seat {
        wl_seat_release(seat)
    }
    if let xkbState = xkbState {
        xkb_state_unref(xkbState)
    }
    if let xkbContext = xkbContext {
        xkb_context_unref(xkbContext)
    }
    libdecor_unref(decorContext)
    wl_display_disconnect(display)
}
```

### 3. **Null Safety**
```swift
// Always check optional C pointers:
guard let display = wl_display_connect(nil) else {
    throw LuminaError.platformError(...)
}

guard let decorContext = libdecor_new(display, nil) else {
    wl_display_disconnect(display)
    throw LuminaError.platformError(...)
}
```

### 4. **MainActor Isolation**
```swift
// All Wayland APIs are @MainActor isolated
@MainActor
struct WaylandApplication: LuminaApp {
    // Prevents data races on Wayland objects
}
```

---

## Comparison: Old vs New

| Aspect | Old Implementation | New Implementation |
|--------|-------------------|-------------------|
| **Decoration** | Manual xdg-decoration | libdecor (automatic SSD/CSD) |
| **CSD Fallback** | ✗ Not implemented | ✓ Automatic via libdecor |
| **Window Creation** | xdg_surface + xdg_toplevel + listeners | libdecor_frame (one call) |
| **Configure Events** | Manual xdg_surface listener | libdecor handles automatically |
| **Compositor Compat** | GNOME, KDE, Sway only | ALL compositors |
| **Code Complexity** | ~2000 lines | ~800 lines (estimated) |
| **Maintenance** | High (custom protocols) | Low (libdecor maintained) |
| **Follows Industry** | ✗ Custom approach | ✓ SDL3/GLFW pattern |

---

## Testing Plan

### Phase 1: Basic Functionality
- ✓ Display connection
- ✓ libdecor context creation
- ✓ Window creation with libdecor_frame
- ✓ Window shows with decorations
- ✓ Event loop processes without crash

### Phase 2: Input Handling
- ✓ Pointer events (move, click)
- ✓ Keyboard events with XKB
- ✓ Modifier keys (Shift, Ctrl, Alt)
- ✓ Text input generation

### Phase 3: Compositor Compatibility
- ✓ Sway (wlroots) - SSD via xdg-decoration
- ✓ GNOME (Mutter) - SSD via xdg-decoration
- ✓ KDE Plasma (KWin) - SSD via xdg-decoration
- ✓ Weston - CSD via libdecor rendering
- ✓ Hyprland - SSD via xdg-decoration

### Phase 4: Edge Cases
- ✓ Window resize
- ✓ Window close (decoration button)
- ✓ Keyboard focus changes
- ✓ Compositor disconnection
- ✓ No XKB keymap

---

## Dependencies

**Runtime:**
- libwayland-client >= 1.18
- libxkbcommon >= 1.0
- libdecor-0 >= 0.1

**Build:**
- wayland-protocols (for protocol XML files, if needed)
- pkg-config

**Ubuntu/Debian:**
```bash
sudo apt install libwayland-dev libxkbcommon-dev libdecor-0-dev
```

**Fedora:**
```bash
sudo dnf install wayland-devel libxkbcommon-devel libdecor-devel
```

---

## Implementation Checklist

### Core Infrastructure
- [x] CWaylandClient C interop module
- [x] Package.swift dependencies
- [ ] WaylandTypes.swift (helper types)
- [ ] WaylandApplication.swift (skeleton)

### Application Lifecycle
- [ ] Display connection
- [ ] libdecor context creation
- [ ] Seat discovery and input setup
- [ ] Event loop (poll/wait/waitUntil)
- [ ] Proper cleanup/deinit

### Window Management
- [ ] libdecor_frame creation
- [ ] Frame interface callbacks (configure, close, commit)
- [ ] Surface and buffer management
- [ ] Window properties (title, size, visibility)
- [ ] Window close lifecycle

### Input Handling
- [ ] Seat capability listener
- [ ] Pointer events (enter, leave, motion, button, axis)
- [ ] Keyboard events (keymap, key, modifiers)
- [ ] XKB state management
- [ ] Text input generation

### Testing & Validation
- [ ] Build on Ubuntu 24.04
- [ ] Test on Sway
- [ ] Test on GNOME
- [ ] Test on Weston
- [ ] Verify no crashes or hangs
- [ ] Verify decorations appear correctly

---

## Next Steps

1. Implement WaylandTypes.swift (utilities)
2. Implement WaylandApplication.swift (display, libdecor, event loop)
3. Implement WaylandWindow.swift (libdecor_frame)
4. Implement WaylandInput.swift (pointer, keyboard, XKB)
5. Test on target compositors
6. Document any compositor-specific quirks

---

## References

- [libdecor documentation](https://gitlab.gnome.org/jadahl/libdecor)
- [SDL3 Wayland backend source](https://github.com/libsdl-org/SDL/blob/main/src/video/wayland/)
- [GLFW Wayland backend source](https://github.com/glfw/glfw/tree/master/src)
- [Wayland Book - libdecor](https://xeechou.net/posts/libdecor/)
