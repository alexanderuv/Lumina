# Lumina (Windowing Library) — Feature-First Strategy & Plan

## Feature Parity Matrix Scaffold

**Legend:**
- ✅ Implemented and working
- 🔨 In progress / needs integration
- ⚠️ Partially implemented
- ❌ Not started

| Feature                                  | macOS | Windows | Linux/X11 | Linux/Wayland |
|------------------------------------------|-------|---------|-----------|---------------|
| **Wave A – Core Windowing & Input**      |       |         |           |               |
| Event loop (run/poll, user events)       | ✅    | ❌      | ✅        | ✅            |
| Window create/show/close                 | ✅    | ❌      | ✅        | ✅            |
| Resize/move/title/focus                  | ✅    | ❌      | ✅        | ✅            |
| DPI/Scaling events                       | ✅    | ❌      | ✅        | ✅            |
| Keyboard (basic)                         | ✅    | ❌      | ✅        | ✅            |
| Mouse input (move/buttons/wheel)         | ✅    | ❌      | ✅        | ✅            |
| System cursors                           | ✅    | ❌      | ✅        | ✅            |
| **Wave B – Redraw & Robustness**         |       |         |           |               |
| Redraw events & frame pacing             | ⚠️    | ❌      | ✅        | ❌            |
| Control flow (Wait/Poll)                 | ✅    | ❌      | ✅        | ✅            |
| Decorations & transparency               | ✅    | ❌      | ⚠️        | ✅            |
| Clipboard (text)                         | ✅    | ❌      | ✅        | ⚠️            |
| Monitor enumeration (basic)              | ✅    | ❌      | ✅        | ✅            |
| **Wave C – Advanced Input & IME**        |       |         |           |               |
| Advanced keyboard mapping                | ❌    | ❌      | ❌        | ❌            |
| IME composition                          | ❌    | ❌      | ❌        | ❌            |
| Pointer lock/confine                     | ❌    | ❌      | ❌        | ⚠️            |
| Raw mouse input                          | ❌    | ❌      | ❌        | ⚠️            |
| **Wave D – Fullscreen & Theming**        |       |         |           |               |
| Borderless fullscreen                    | ❌    | ❌      | ❌        | ❌            |
| Exclusive fullscreen                     | ❌    | ❌      | ❌        | ❌            |
| Theme change events                      | ❌    | ❌      | ❌        | ❌            |
| Window icons & badges                    | ❌    | ❌      | ❌        | ❌            |
| **Wave E – Clipboard & Drag/Drop**       |       |         |           |               |
| Clipboard (rich: HTML, PNG, file URIs)   | ❌    | ❌      | ❌        | ❌            |
| Drag & Drop receive                      | ❌    | ❌      | ❌        | ❌            |
| Drag & Drop source                       | ❌    | ❌      | ❌        | ❌            |
| **Wave F – Polish & Power Events**       |       |         |           |               |
| Power/session events                     | ❌    | ❌      | ❌        | ❌            |
| Decorationsless window movement          | ❌    | ❌      | ❌        | ❌            |
| Transparency/vibrancy                    | ❌    | ❌      | ❌        | ❌            |
| Notifications & badging hooks            | ❌    | ❌      | ❌        | ❌            |

---

## Linux/X11 Implementation Notes

**Current Status:** Wave A & B Core Features - Complete

**Completed Features:**
- Full event loop implementation (run/poll/wait/waitUntil) with timeout support
- Complete window lifecycle (create/show/hide/close)
- Window operations (resize/move/setTitle/focus)
- XRandR-based DPI/HiDPI detection from physical dimensions
- Full keyboard input via XKB (X keyboard extension)
  - Keymap support for all layouts
  - Modifier key tracking (Shift, Control, Alt, Super)
  - Text input with UTF-8 encoding
- Complete mouse input (buttons, motion, wheel, enter/exit)
- System cursors (arrow, ibeam, crosshair, hand, resize cursors)
  - Cursor font-based implementation (XCB cursor font glyphs)
  - set/hide/show operations
  - Invisible cursor for hiding
- Control flow modes (Wait/Poll/WaitUntil with file descriptor select)
- Window decorations toggle (via Motif WM hints)
- Always-on-top windows (via _NET_WM_STATE_ABOVE EWMH property)
- Text clipboard via CLIPBOARD selection protocol
  - Read with SelectionNotify event handling
  - Write with selection ownership
  - Synchronous API with 1s timeout
- Full monitor enumeration via XRandR extension
  - Output detection (connected, active, position, size)
  - Primary monitor detection
  - Physical dimension-based DPI scaling
  - Monitor change notifications
- Redraw events (expose events, requestRedraw via xcb_clear_area)

**Partial Implementation:**
- Window decorations (decorations toggle works, transparency not supported)

**Not Supported:**
- Transparency (requires ARGB visual at window creation time)

**Architecture:**
- Built on XCB (X protocol C-Binding)
- XKB integration for keyboard support via libxkbcommon
- XRandR for monitor enumeration and DPI detection
- EWMH (Extended Window Manager Hints) for modern WM features
- ICCCM protocols (WM_DELETE_WINDOW, etc.)
- Synchronous clipboard via selection protocol

**Files:**
- `X11Application.swift` - Event loop and application lifecycle
- `X11Window.swift` - Window management and operations
- `X11Input.swift` - Keyboard/mouse event translation with XKB
- `X11Monitor.swift` - XRandR-based monitor enumeration
- `X11Clipboard.swift` - CLIPBOARD selection protocol implementation
- `X11Atoms.swift` - Cached X11 atoms for protocol communication
- `X11Platform.swift` - Platform initialization and XCB connection
- `X11Capabilities.swift` - Capability detection

---

## macOS Implementation Notes

**Current Status:** Wave A & B Core Features - Complete

**Completed Features:**
- Full event loop implementation (run/poll/wait/waitUntil)
- Complete window lifecycle (create/show/hide/close)
- Window operations (resize/move/setTitle/focus/min/max size)
- DPI/HiDPI support via NSScreen backingScaleFactor
- Full keyboard input with modifier keys and text input
- Complete mouse input (buttons, movement, wheel, enter/exit)
- System cursor support (arrow, ibeam, crosshair, hand, resize)
- Control flow modes (Wait/Poll/WaitUntil)
- Window decorations toggle (bordered/borderless)
- Transparency and always-on-top windows
- Text clipboard (read/write/change detection)
- Full monitor enumeration with work area
- ProMotion (dynamic refresh rate) detection
- Retina scaling support

**Partial Implementation:**
- Redraw events (requestRedraw implemented, frame pacing not yet integrated)

**Architecture:**
- Built on AppKit (NSApplication, NSWindow, NSScreen, NSPasteboard)
- MainActor isolation for thread safety
- Event translation from NSEvent to Lumina's unified Event type
- Coordinate system conversion (AppKit bottom-left → Lumina top-left)

**Files:**
- `MacApplication.swift` - Event loop and application lifecycle
- `MacWindow.swift` - Window management and operations
- `MacInput.swift` - Keyboard/mouse event translation
- `MacMonitor.swift` - Display enumeration using NSScreen
- `MacClipboard.swift` - Clipboard operations using NSPasteboard

---

## Linux/Wayland Implementation Notes

**Current Status:** Wave A Core Features - Complete, Wave B Mostly Complete

**✅ VERIFIED WORKING** (Tested with WaylandDemo):
- ✅ Platform initialization and Wayland connection
- ✅ Monitor enumeration (via wl_output)
- ✅ Event loop (run/poll/wait/waitUntil) with proper file descriptor polling
- ✅ User event posting (thread-safe queue)
- ✅ Window creation, show, and lifecycle management
- ✅ Window resize, move, title, focus operations
- ✅ Dynamic libdecor loading and initialization
- ✅ GLFW-style 3-tier decoration fallback (libdecor → SSD → CSD)
- ✅ Keyboard input (full XKB integration via libxkbcommon)
- ✅ Mouse input (buttons, motion, wheel, enter/exit)
- ✅ Control flow modes (Wait/Poll/WaitUntil)
- ✅ Platform/application separation architecture
- ✅ Swift 6.2 concurrency (MainActor isolation, Sendable conformance)

**DPI/Scaling Implementation (GLFW Pattern - Complete!):**
- ✅ wl_surface enter/leave event tracking
- ✅ Per-window output tracking (which monitors window occupies)
- ✅ Buffer scale calculation (max scale across all outputs)
- ✅ `wl_surface_set_buffer_scale()` integration
- ✅ Window.scaleFactor() returns actual scale
- ✅ Scale change events emitted to application (WindowEvent.scaleFactorChanged)
- ✅ EGL window resize on scale change
- ✅ Compositor preferred_buffer_scale (Wayland v6+) support
- ⚠️ Testing needed (surface enter/leave events may fire after window map)

**Partial/In Progress:**
- ⚠️ Clipboard (wl_data_device_manager bound, read/write not implemented)

**Protocol Support:**
- ✅ wl_compositor v4 (surface creation)
- ✅ wl_shm v1 (shared memory buffers)
- ✅ wl_seat v5 (input device management)
- ✅ wl_subcompositor v1 (for CSD decorations)
- ✅ wl_data_device_manager v3 (clipboard/DnD)
- ✅ wp_viewporter v1 (HiDPI scaling)
- ✅ zwp_pointer_constraints_v1 (pointer locking)
- ✅ zwp_relative_pointer_manager_v1 (raw mouse motion)
- ✅ zxdg_decoration_manager_v1 (SSD negotiation)
- ✅ xdg_wm_base (xdg-shell window management)

**Architecture:**
- Built on Wayland core protocol + xdg-shell
- Dynamic libdecor loading via dlopen (GLFW pattern)
- XKB integration for keyboard via libxkbcommon
- MainActor-isolated with @unchecked Sendable for C callback safety
- Proper event loop with wl_display_prepare_read/read_events pattern

**Build System:**
- ✅ No compile-time libdecor dependency
- ✅ Wayland protocol generation via SPM plugins
- ✅ Graceful fallback when libdecor unavailable
- ✅ Compiles and runs on all Wayland compositors
