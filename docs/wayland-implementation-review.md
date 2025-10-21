# Lumina Wayland Implementation - Comprehensive Review & Recommendations

**Date:** 2025-10-20
**Status:** Current implementation incomplete - requires libdecor migration
**Priority:** HIGH - Architecture decision needed before continuing

---

## Executive Summary

The current Wayland implementation is **architecturally incomplete** and requires migration to **libdecor** for production use. While the core protocol handling is sound, the decoration approach (xdg-decoration only) is insufficient and doesn't match industry standards used by SDL3, GLFW, and other major projects.

**Recommendation:** Migrate to libdecor (2-3 day effort) rather than fixing current approach (2+ week effort).

---

## Current Implementation Status

### ✅ What's Working
- Wayland display connection and protocol enumeration
- wl_compositor, xdg_wm_base, wl_seat, wl_shm binding
- Basic window creation with xdg-shell
- Shared memory buffer allocation
- XKB keyboard handling integration (partially)
- Event queue architecture

### ❌ Critical Issues

1. **Missing xdg_toplevel Listener** ⚠️ CRASH
   - File: `WaylandWindow.swift:130-134`
   - Issue: xdg_toplevel created but no listener attached
   - Impact: Protocol violation, configure events not acknowledged, causes crashes
   - **This is why you're seeing crashes**

2. **No Input System Initialization** ⚠️ HANG
   - File: `WaylandApplication.swift` (init method)
   - Issue: Input state created but never connected to event loop
   - Impact: Events dispatched but never transferred to app queue
   - **This is why window appears frozen**

3. **Incomplete Decoration Handling** ⚠️ NO DECORATIONS ON SOME COMPOSITORS
   - Current: Only uses `zxdg_decoration_manager_v1` (optional protocol)
   - Missing: Client-side decoration (CSD) fallback
   - Impact: No decorations on Weston, custom compositors without xdg-decoration
   - **Not all compositors support xdg-decoration**

4. **Event Loop Pattern Bugs**
   - File: `WaylandApplication.swift:373-394` (poll case)
   - Issue: Not checking `wl_display_prepare_read()` return value
   - Impact: Can skip events or double-read

### ⚠️ Medium Priority Issues

5. **No Monitor Enumeration** - `WaylandMonitor` exists but not integrated
6. **No Clipboard Support** - Code exists but not connected
7. **Missing Cursor Implementation** - Stubbed out
8. **Scale Factor Returns 1.0** - HiDPI broken
9. **Unnecessary Surface Commits** - Performance impact in setTitle(), etc.

---

## Why libdecor is Essential

### What is libdecor?

**libdecor is NOT just a wrapper around xdg-decoration.** It's a complete decoration solution:

1. **Automatic SSD/CSD Selection**
   - Queries compositor for xdg-decoration support
   - Uses SSD when available (GNOME, KDE, Sway)
   - **Falls back to CSD when not** (Weston, minimal compositors)

2. **Provides CSD Rendering**
   - Renders title bars, buttons, borders when needed
   - Theme integration (GTK themes on GNOME, etc.)
   - Hit testing for resize edges, title bar drag
   - Button event handling (minimize, maximize, close)

3. **Protocol Abstraction**
   - Hides xdg-surface/xdg-toplevel complexity
   - Handles configure/commit lifecycle
   - Manages window state transitions

### Your Current Approach vs. libdecor

| Feature | Current (xdg-decoration only) | With libdecor |
|---------|------------------------------|---------------|
| **SSD when available** | ✓ | ✓ |
| **CSD fallback** | ✗ Need 500+ lines | ✓ Automatic |
| **Theme integration** | ✗ Manual | ✓ Automatic |
| **Decoration events** | ✗ Manual | ✓ Automatic |
| **Compositor compatibility** | GNOME, KDE, Sway only | **ALL compositors** |
| **Maintenance burden** | High | Low |
| **Matches industry standard** | ✗ | ✓ (SDL3, GLFW, Electron) |

### Compositor Compatibility Matrix

| Compositor | xdg-decoration Support | Current Code | With libdecor |
|------------|----------------------|--------------|---------------|
| GNOME (Mutter) | ✓ SSD | ✓ Works | ✓ Works (SSD) |
| KDE Plasma (KWin) | ✓ SSD | ✓ Works | ✓ Works (SSD) |
| Sway (wlroots) | ✓ SSD | ✓ Works | ✓ Works (SSD) |
| Weston | ✗ No support | **✗ No decorations** | ✓ Works (CSD) |
| Hyprland | ✓ SSD | ✓ Works | ✓ Works (SSD) |
| Custom/Minimal | Varies | **✗ Broken** | ✓ Works (auto CSD/SSD) |

**Without libdecor, your windows will have no title bar or buttons on Weston (the reference compositor).**

---

## Industry Research: SDL3 & GLFW

### SDL3 Architecture

**Decoration Strategy:**
```c
#ifdef HAVE_LIBDECOR_H
    // PRIMARY PATH - libdecor
    window->shell_surface.libdecor.frame = libdecor_decorate(...)
#else
    // FALLBACK - raw xdg-toplevel without decorations
    window->shell_surface.xdg.surface = xdg_wm_base_get_xdg_surface(...)
#endif
```

**Key Insight:** SDL3 treats libdecor as **PRIMARY**, not optional.

**Event Loop Integration:**
```c
// Each frame:
libdecor_dispatch(decorContext, 0);  // Dispatch libdecor events
wl_display_dispatch_pending(display);  // Then Wayland events
wl_display_flush(display);
```

**Hints:**
- `SDL_HINT_VIDEO_WAYLAND_ALLOW_LIBDECOR` - use libdecor when xdg-decoration unavailable
- `SDL_HINT_VIDEO_WAYLAND_PREFER_LIBDECOR` - always use libdecor even if xdg-decoration available

### GLFW Architecture

**Decoration Strategy:**
```c
#ifdef HAVE_LIBDECOR_H
    window->wl.libdecor.frame = libdecor_decorate(...)
    // libdecor handles configure events, rendering, etc.
#else
    // Manual CSD implementation using wl_subsurface
    // ~500 lines of decoration rendering code
#endif
```

**GLFW 3.3.9+** added libdecor as preferred method (2023).

### Common Pattern

Both projects:
1. Use libdecor as **primary** decoration path
2. Integrate via `libdecor_dispatch()` in event loop
3. Let libdecor handle xdg-surface configure complexity
4. Only implement raw xdg-toplevel as build-time fallback if libdecor unavailable

---

## Critical Bugs (Regardless of libdecor Decision)

### Bug #1: Missing xdg_toplevel Listener ⚠️ CRITICAL

**Location:** `WaylandWindow.swift:130-134`

**Current Code:**
```swift
guard let xdgToplevel = xdg_surface_get_toplevel(xdgSurface) else {
    // ... error handling ...
}
// ← NO LISTENER ADDED!
xdg_toplevel_set_title(xdgToplevel, cString)
```

**Problem:** xdg-shell protocol **requires** listening to configure events from xdg_toplevel.

**Fix Required:**
```swift
let toplevelListener = UnsafeMutablePointer<xdg_toplevel_listener>.allocate(capacity: 1)
toplevelListener.pointee = xdg_toplevel_listener(
    configure: { (data, toplevel, width, height, states) in
        // Handle resize, maximize, fullscreen state changes
        // Must apply configuration and commit surface
    },
    close: { (data, toplevel) in
        // Handle close request from compositor (user clicked X)
    }
)
xdg_toplevel_add_listener(xdgToplevel, toplevelListener, windowDataPtr)
// Store toplevelListener for cleanup in close()
```

**Why this causes crashes:** Compositor sends configure events, but no handler → undefined behavior.

### Bug #2: Input Events Never Reach Application ⚠️ CRITICAL

**Location:** `WaylandApplication.swift:pumpEvents()`

**Problem:** Input events queued in `WaylandInputState.eventQueue`, but never transferred to application `EventQueue`.

**Current Code:**
```swift
// Input listeners enqueue to WaylandInputState.eventQueue
// pumpEvents() only checks application EventQueue
// → Events never reach application!
```

**Fix:** Already implemented in current working directory - events now transferred.

### Bug #3: Incorrect poll() Event Loop Pattern

**Location:** `WaylandApplication.swift:373-394`

**Current Code:**
```swift
case .poll:
    _ = wl_display_prepare_read(display)  // ← Not checking return!
    _ = wl_display_read_events(display)
```

**Problem:** `wl_display_prepare_read()` returns error if events pending. Ignoring return value can cause event loss.

**Correct Pattern:**
```swift
case .poll:
    // Dispatch pending events first
    while lumina_wl_display_dispatch_pending(display) > 0 { }

    // Then check for new events
    while wl_display_prepare_read(display) != 0 {
        lumina_wl_display_dispatch_pending(display)
    }

    // Non-blocking socket check...
```

---

## Recommended Architecture: libdecor Migration

### Dependencies to Add

**Package.swift:**
```swift
.systemLibrary(
    name: "CWaylandLinux",
    pkgConfig: "wayland-client xkbcommon libdecor-0",  // ← Add libdecor-0
    providers: [
        .apt(["libwayland-dev", "libxkbcommon-dev", "libdecor-0-dev"]),
        .yum(["wayland-devel", "libxkbcommon-devel", "libdecor-devel"])
    ]
)
```

### Swift Bindings

**Sources/CInterop/CWaylandLinux/module.modulemap:**
```c
module CWaylandLibdecor {
    header "libdecor_shims.h"
    link "decor-0"
    export *
}
```

**libdecor_shims.h:**
```c
#include <libdecor-0/libdecor.h>

// Helpers for Swift interop
static inline struct libdecor *
lumina_libdecor_new(struct wl_display *display) {
    return libdecor_new(display, NULL);
}
```

### WaylandApplication Changes

**Add libdecor context:**
```swift
@MainActor
struct WaylandApplication: LuminaApp {
    private let display: OpaquePointer
    private let decorContext: OpaquePointer  // libdecor*

    init() throws {
        // ... wl_display_connect ...

        guard let decor = libdecor_new(display, nil) else {
            throw LuminaError.platformError(...)
        }
        self.decorContext = decor
    }

    mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
        // Add libdecor dispatch BEFORE Wayland dispatch
        libdecor_dispatch(decorContext, 0)

        // ... rest of event loop ...
    }
}
```

### WaylandWindow Changes

**Replace xdg-toplevel with libdecor frame:**

**Old (remove):**
```swift
let xdgSurface = xdg_wm_base_get_xdg_surface(wmBase, surface)
let xdgToplevel = xdg_surface_get_toplevel(xdgSurface)
let xdgDecoration = zxdg_decoration_manager_v1_get_toplevel_decoration(...)
```

**New:**
```swift
let frameInterface = libdecor_frame_interface(
    configure: { (frame, configuration, userData) in
        // libdecor provides configured size, state
        var width: Int32 = 0, height: Int32 = 0
        libdecor_configuration_get_content_size(configuration, frame, &width, &height)

        // Apply configuration
        let state = libdecor_state_new(width, height)
        libdecor_frame_commit(frame, state, configuration)
        libdecor_state_free(state)
    },
    close: { (frame, userData) in
        // Handle close request
    },
    commit: { (frame, userData) in
        // Handle commit callback
    }
)

let frame = libdecor_decorate(
    decorContext,
    surface,
    &frameInterface,
    Unmanaged.passUnretained(self).toOpaque()
)

libdecor_frame_set_title(frame, title)
libdecor_frame_commit(frame, nil, nil)
```

**Benefits:**
- ✓ Automatic SSD/CSD selection
- ✓ No manual xdg-surface configure handling
- ✓ No manual decoration protocol code
- ✓ Works on all compositors

---

## Implementation Comparison

### Option A: Fix Current Implementation (NOT RECOMMENDED)

**Effort:** 2+ weeks

**Tasks:**
1. Add xdg_toplevel listener (1 day)
2. Fix event loop patterns (1 day)
3. Implement monitor enumeration (2 days)
4. **Implement CSD fallback (1-2 weeks)**:
   - wl_subsurface for decoration layers
   - Cairo/rendering for title bar, buttons, borders
   - Hit testing for resize edges, drag areas
   - Button event handling
   - Theme integration
5. Test across compositors (2-3 days)

**Result:** ~500 lines of decoration code you maintain forever.

### Option B: Migrate to libdecor (RECOMMENDED)

**Effort:** 2-3 days

**Tasks:**
1. Add libdecor dependency to Package.swift (30 min)
2. Create Swift bindings (shims.h, modulemap) (2 hours)
3. Replace WaylandWindow decoration code (1 day)
4. Add libdecor_dispatch to event loop (1 hour)
5. Fix critical bugs (xdg_toplevel listener if still using raw protocol, event loop) (4 hours)
6. Test across compositors (4 hours)

**Result:**
- ✓ Industry-standard approach
- ✓ Works on all compositors
- ✓ libdecor maintained by Wayland community
- ✓ No custom decoration code

---

## Testing Strategy

### Compositor Test Matrix

| Compositor | Priority | Purpose | Expected Behavior |
|------------|----------|---------|-------------------|
| **Sway** | ⭐⭐⭐ | Strict protocol compliance | libdecor → SSD via xdg-decoration |
| **GNOME** | ⭐⭐⭐ | Most users | libdecor → SSD via xdg-decoration |
| **KDE Plasma** | ⭐⭐ | Second most users | libdecor → SSD via xdg-decoration |
| **Weston** | ⭐⭐ | Reference, no xdg-decoration | libdecor → CSD (manual rendering) |
| **Hyprland** | ⭐ | Modern tiling compositor | libdecor → SSD via xdg-decoration |

### Debug Tools

**Protocol Debugging:**
```bash
WAYLAND_DEBUG=1 ./WaylandDemo 2>&1 | tee wayland.log
# Shows all protocol messages - use for crash analysis
```

**Protocol Enumeration:**
```bash
wayland-info  # Shows all protocols advertised by compositor
```

**Nested Testing:**
```bash
# Test without full DE:
weston  # Run Weston in window
# Then run app inside nested compositor
```

---

## Migration Plan

### Phase 1: Critical Fixes (1 day)
- ✓ Add xdg_toplevel listener
- ✓ Fix poll() event loop pattern
- ✓ Fix input event transfer (already done)
- Test that window doesn't crash

### Phase 2: libdecor Integration (2 days)
- Add libdecor-0 dependency
- Create Swift bindings
- Replace decoration code with libdecor
- Test on Sway, GNOME, Weston

### Phase 3: Complete Core Features (1 week)
- Implement wl_output protocol (monitor enumeration)
- Connect clipboard implementation
- Add cursor theme support via libwayland-cursor
- Test across all target compositors

### Phase 4: Polish (ongoing)
- Implement fractional scaling (wp_fractional_scale_v1)
- Optimize buffer management
- Add proper error recovery

---

## Conclusion

**Primary Recommendation:** **Migrate to libdecor immediately.**

The current xdg-decoration-only approach is architecturally incomplete and doesn't match industry standards. libdecor is:
- Used by SDL3, GLFW, Electron, and all major Wayland applications
- Provides automatic SSD/CSD fallback
- Handles decoration complexity automatically
- Maintained by the Wayland community
- Required for compatibility with all compositors

**Estimated Effort:**
- libdecor migration: **2-3 days**
- Fix current approach: **2+ weeks** (and you maintain decoration code forever)

**Next Steps:**
1. Review this document with team
2. Decide on libdecor migration
3. Execute Phase 1 critical fixes
4. Begin Phase 2 libdecor integration

---

## References

- [libdecor documentation](https://xeechou.net/posts/libdecor/)
- [SDL3 Wayland backend](https://github.com/libsdl-org/SDL/tree/main/src/video/wayland)
- [GLFW Wayland backend](https://github.com/glfw/glfw/tree/master/src/wl_*.c)
- [Wayland Book - Event Loop](https://wayland-book.com/wayland-display/event-loop.html)
- [xdg-shell protocol spec](https://wayland.app/protocols/xdg-shell)
