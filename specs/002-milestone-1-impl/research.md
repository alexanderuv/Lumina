# Phase 0: Research & Technical Context

**Feature**: Milestone 1 - Linux Support (X11/Wayland) + macOS Wave B
**Date**: 2025-10-20
**Status**: Complete

---

## Overview

This research phase establishes the technical foundation for extending Lumina's windowing system to Linux (X11 and Wayland) while enhancing macOS with Wave B features (redraw contract, control flow modes, window decorations, clipboard, monitor enumeration).

**Prerequisites Met**: M0 architecture analysis confirms solid foundation with protocol-based abstractions, unified event system, DPI/scaling support, and Swift 6.2 strict concurrency.

---

## 1. Linux Windowing Systems Research

### 1.1 X11 Backend (XCB)

**Decision**: Use **XCB (X protocol C-Binding)** over Xlib
**Rationale**: Better async support, lower-level control, cleaner Swift bindings, thread-safe by design

#### Key XCB Components

**Connection & Event Loop**
```c
xcb_connection_t *connection = xcb_connect(display_name, &screen_num);
xcb_generic_event_t *event = xcb_wait_for_event(connection);  // Blocking
xcb_generic_event_t *event = xcb_poll_for_event(connection);  // Non-blocking
```

- Single connection per application (M0 pattern: single EventLoop)
- Thread-safe event retrieval with lock-free queue
- File descriptor (`xcb_get_file_descriptor()`) integrable with Dispatch or custom run loop

**Window Creation & Management**
```c
xcb_window_t window = xcb_generate_id(connection);
xcb_create_window(connection, depth, window, parent, x, y, width, height,
                  border_width, class, visual, value_mask, value_list);
xcb_map_window(connection, window);  // Show
xcb_unmap_window(connection, window);  // Hide
xcb_destroy_window(connection, window);
```

- EWMH (Extended Window Manager Hints) for size constraints, decorations, always-on-top:
  - `_NET_WM_STATE` (fullscreen, above, below, hidden)
  - `_NET_WM_WINDOW_TYPE` (normal, dialog, utility)
  - `WM_NORMAL_HINTS` (min/max size, aspect ratio)
  - `_NET_FRAME_EXTENTS` (border sizes)

**Event Types** (matches M0 event system closely)
- `XCB_EXPOSE` → RedrawRequested (Wave B)
- `XCB_CONFIGURE_NOTIFY` → Resized/Moved
- `XCB_BUTTON_PRESS/RELEASE` → PointerEvent.buttonPressed/Released
- `XCB_MOTION_NOTIFY` → PointerEvent.moved
- `XCB_ENTER_NOTIFY/LEAVE_NOTIFY` → PointerEvent.entered/left
- `XCB_KEY_PRESS/RELEASE` → KeyboardEvent.keyDown/keyUp
- `XCB_FOCUS_IN/FOCUS_OUT` → WindowEvent.focused/unfocused

**DPI Detection Strategy** (priority order)
1. **Xft.dpi** resource: `xcb_xrm_get_resource()` from `~/.Xresources`
2. **XSETTINGS daemon**: Query `Xft/DPI` key (GNOME/KDE/Xfce)
3. **Physical dimensions**: Calculate from screen width_in_millimeters
4. **Fallback**: 96 DPI (1.0x scale factor)

**XInput2 for Advanced Input**
- High-precision scroll deltas (smooth scrolling)
- Additional mouse buttons (4+)
- Touch/tablet events (future)

**XKB (X Keyboard Extension)**
- Keymap translation (physical scan codes → key symbols)
- Modifier state tracking (Shift, Ctrl, Alt, Super)
- Repeat rate configuration

**Atom Caching** (performance optimization)
- Cache frequently used atoms at startup:
  - `WM_PROTOCOLS`, `WM_DELETE_WINDOW`
  - `_NET_WM_STATE`, `_NET_WM_STATE_FULLSCREEN`, `_NET_WM_STATE_ABOVE`
  - `_NET_WM_NAME`, `_NET_WM_ICON_NAME`
- Use `xcb_intern_atom()` with `only_if_exists=1` for detection

**Error Handling**
- X11 errors are **asynchronous** (arrive later)
- Install error handler: `xcb_request_check()` for critical operations
- Avoid crashes on WM protocol violations

#### Swift XCB Integration Pattern

```swift
@MainActor
struct X11Application: LuminaApp {
    private let connection: OpaquePointer  // xcb_connection_t*
    private let screen: OpaquePointer      // xcb_screen_t*
    private let wmDeleteWindow: UInt32     // Cached atom
    private var eventQueue: [Event] = []
    private var windowRegistry = WindowRegistry<UInt32>()  // xcb_window_t -> WindowID

    init() throws {
        guard let conn = xcb_connect(nil, nil) else {
            throw LuminaError.platformInitializationFailed("XCB connection failed")
        }
        self.connection = conn
        // Setup screen, atoms, XInput2, XKB
    }

    mutating func poll() -> Event? {
        while let xcbEvent = xcb_poll_for_event(connection) {
            if let luminaEvent = translateXCBEvent(xcbEvent) {
                eventQueue.append(luminaEvent)
            }
        }
        return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
    }
}
```

**Dependencies**
- libxcb (core protocol)
- libxcb-keysyms (keyboard utilities)
- libxcb-xkb (keyboard extension)
- libxcb-xinput (XInput2)
- libxkbcommon (keymap interpretation)

**Compatibility**: Works on all X11-based systems (GNOME X11, KDE X11, i3, Openbox, Xfce, etc.)

---

### 1.2 Wayland Backend

**Decision**: Use **wayland-client** with **xdg-shell** protocol for core windowing
**Rationale**: Modern compositor protocol, HiDPI native, future-proof for GNOME/KDE/Sway

#### Core Wayland Protocols

**Protocol Bindings**
- Generate Swift bindings from XML specs (`wayland.xml`, `xdg-shell.xml`)
- Or use C API directly with Swift interop (similar to Win32 pattern in M0)

**Essential Protocols**
1. **wl_display** - Connection to compositor
2. **wl_registry** - Global object discovery (enumerate available interfaces)
3. **wl_compositor** - Create surfaces
4. **wl_surface** - Window surface (rendering target)
5. **xdg_wm_base** - Window management base protocol
6. **xdg_surface** - Surface role assignment
7. **xdg_toplevel** - Top-level window (desktop window with title bar)
8. **wl_seat** - Input device group (keyboard, pointer, touch)
9. **wl_pointer** - Mouse/touchpad events
10. **wl_keyboard** - Keyboard events (uses libxkbcommon for keymap)

**Window Creation Flow**
```c
wl_surface *surface = wl_compositor_create_surface(compositor);
xdg_surface *xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, surface);
xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg_surface);

xdg_toplevel_set_title(toplevel, "Window Title");
xdg_toplevel_set_min_size(toplevel, 100, 100);
xdg_toplevel_set_max_size(toplevel, 1920, 1080);

wl_surface_commit(surface);  // Apply changes
```

**Event Handling**
```c
wl_display_dispatch(display);       // Blocking (like wait())
wl_display_dispatch_pending(display);  // Non-blocking (like poll())
wl_display_get_fd(display);         // File descriptor for select/epoll
```

- Event callbacks registered per protocol object
- `xdg_toplevel_add_listener()` for window events
- `wl_pointer_add_listener()` for mouse events
- `wl_keyboard_add_listener()` for keyboard events

**DPI/Scaling**
- **wl_output** interface provides scale factor per monitor
- **wp_fractional_scale_v1** (optional protocol) for precise fractional scaling (1.25x, 1.5x)
- Compositor hints preferred scale via `wl_surface.preferred_buffer_scale`
- Surface scale set via `wl_surface_set_buffer_scale(surface, scale)`

**Client-Side Decorations (CSD)**
- Wayland has **no server-side decorations by default** (unlike X11)
- Options:
  1. **libdecor** library - Integrates with desktop theme (GNOME, KDE)
  2. **Custom decorations** - Render title bar manually (more control, more work)
  3. **xdg-decoration** protocol - Request SSD if compositor supports (KDE Plasma)

**Decision**: Use **libdecor** for M1
**Rationale**: Theme consistency, minimal code, fallback to CSD if unavailable

**Capability Detection**
```c
wl_registry_add_listener(registry, &registry_listener, userdata);

// In callback:
void global_handler(void *data, struct wl_registry *registry,
                    uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_seat_interface.name) == 0) {
        // Bind seat interface
    } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
        // Bind xdg_wm_base
    } else if (strcmp(interface, wp_fractional_scale_manager_v1_interface.name) == 0) {
        // Optional: bind fractional scale
    }
}
```

- Check protocol version availability at runtime
- Error if essential protocols missing (xdg-shell v2+ required)

**Buffer Management**
- **wl_shm** (shared memory) for initial implementation
  - CPU-based rendering (no GPU acceleration)
  - Simple mmap-based buffer creation
  - Sufficient for UI/windowing (defer GPU to graphics milestone)

**Keyboard Handling**
- Wayland uses **libxkbcommon** (same as X11)
- Compositor sends keymap as file descriptor
- Application parses keymap and translates key codes

#### Swift Wayland Integration Pattern

```swift
@MainActor
struct WaylandApplication: LuminaApp {
    private let display: OpaquePointer      // wl_display*
    private let compositor: OpaquePointer   // wl_compositor*
    private let wmBase: OpaquePointer       // xdg_wm_base*
    private let seat: OpaquePointer         // wl_seat*
    private var eventQueue: [Event] = []
    private var windowRegistry = WindowRegistry<UInt32>()  // wl_surface ID -> WindowID

    init() throws {
        guard let disp = wl_display_connect(nil) else {
            throw LuminaError.platformInitializationFailed("Wayland connection failed")
        }
        self.display = disp
        // Bind registry, enumerate globals, bind essential protocols
        // Setup libxkbcommon context
    }

    mutating func poll() -> Event? {
        wl_display_dispatch_pending(display)  // Process queued events
        return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
    }
}
```

**Dependencies**
- libwayland-client (core protocol)
- libxkbcommon (keyboard handling)
- libdecor (optional, for themed decorations)

**Compatibility**: GNOME Wayland, KDE Plasma (Wayland session), Sway, Weston, Mutter

**Fallback Strategy**: If Wayland not available (no WAYLAND_DISPLAY env var), fall back to X11 backend

---

### 1.3 Linux Backend Selection Strategy

**Runtime Detection**
```swift
#if os(Linux)
public func createLuminaApp() throws -> some LuminaApp {
    if let waylandDisplay = getenv("WAYLAND_DISPLAY"), waylandDisplay != nil {
        return try WaylandApplication()
    } else if let x11Display = getenv("DISPLAY"), x11Display != nil {
        return try X11Application()
    } else {
        throw LuminaError.platformInitializationFailed("No display server detected")
    }
}
#endif
```

**Explicit Selection** (future API)
```swift
public enum LinuxBackend {
    case auto  // Environment-based detection
    case x11
    case wayland
}

public func createLuminaApp(backend: LinuxBackend = .auto) throws -> some LuminaApp
```

**Shared Linux Infrastructure**
- `LinuxMonitor.swift` - RandR (X11) or wl_output (Wayland) abstraction
- `LinuxInput.swift` - Shared keycode normalization (both use libxkbcommon)
- `LinuxCursor.swift` - Cursor theme loading (X11: Xcursor, Wayland: cursor-shape-v1)

---

## 2. macOS Wave B Features Research

### 2.1 Redraw Contract (RedrawRequested Events)

**Current M0 State**: No explicit redraw events; applications must track invalidation manually

**Goal**: Explicit `Event.redraw(RedrawEvent)` with:
- Window ID
- Optional dirty rectangle
- Frame pacing synchronization

#### NSView Integration Strategy

**Option A: Custom NSView subclass**
```swift
class LuminaContentView: NSView {
    var onRedrawRequested: ((NSRect?) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        onRedrawRequested?(dirtyRect)
    }

    override var wantsUpdateLayer: Bool { false }  // Force draw(_:)
}
```

**Option B: CADisplayLink for frame pacing**
```swift
let displayLink = CADisplayLink(target: self, selector: #selector(frameCallback))
displayLink.add(to: .main, forMode: .default)

@objc func frameCallback(_ displayLink: CADisplayLink) {
    for windowID in windowsNeedingRedraw {
        eventQueue.append(.redraw(RedrawEvent(windowID: windowID, dirtyRect: nil)))
    }
}
```

**Decision**: Hybrid approach
- Use **NSView.draw(_:)** for system-initiated redraws (resize, expose)
- Use **CADisplayLink** for application-requested animation frames
- Coalesce multiple `setNeedsDisplay()` calls during live resize

**API Surface**
```swift
public enum RedrawEvent: Sendable {
    case requested(WindowID, dirtyRect: LogicalRect?)
}

extension LuminaWindow {
    func requestRedraw()  // Triggers setNeedsDisplay() or marks for next frame
}
```

**Resize Coalescing**
```swift
override var inLiveResize: Bool {
    didSet {
        if inLiveResize {
            // Start coalescing timer (16ms intervals for 60Hz)
        } else {
            // Flush final resize event
        }
    }
}
```

---

### 2.2 Control Flow Modes

**Current M0 State**: Only `run()` (blocking) and `poll()` (non-blocking)

**New Requirements**:
1. **Wait mode** - Block until event (existing `run()` behavior)
2. **Poll mode** - Immediate return (existing `poll()` behavior)
3. **WaitUntil mode** - Block with deadline

#### Implementation Strategy

**Extend LuminaApp Protocol**
```swift
public enum ControlFlowMode {
    case wait          // Block indefinitely
    case poll          // Return immediately
    case waitUntil(Deadline)  // Block until deadline or event
}

public struct Deadline: Sendable {
    let date: Date
    init(seconds: TimeInterval) {
        self.date = Date(timeIntervalSinceNow: seconds)
    }
}

extension LuminaApp {
    mutating func pumpEvents(mode: ControlFlowMode = .wait) -> Event?
}
```

**macOS NSRunLoop Integration**
```swift
mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
    let timeout: Date = switch mode {
    case .wait:
        .distantFuture
    case .poll:
        .distantPast
    case .waitUntil(let deadline):
        deadline.date
    }

    while let nsEvent = NSApp.nextEvent(matching: .any, until: timeout,
                                        inMode: .default, dequeue: true) {
        NSApp.sendEvent(nsEvent)
        if let event = processQueuedEvents() {
            return event
        }
        if mode == .poll { break }
    }
    return processQueuedEvents()
}
```

**Windows Message Pump**
```swift
mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
    var msg = MSG()

    switch mode {
    case .wait:
        GetMessageW(&msg, nil, 0, 0)
        TranslateMessage(&msg); DispatchMessageW(&msg)

    case .poll:
        while PeekMessageW(&msg, nil, 0, 0, PM_REMOVE) != 0 {
            TranslateMessage(&msg); DispatchMessageW(&msg)
        }

    case .waitUntil(let deadline):
        let timeoutMs = max(0, Int(deadline.date.timeIntervalSinceNow * 1000))
        MsgWaitForMultipleObjects(0, nil, FALSE, DWORD(timeoutMs), QS_ALLINPUT)
        while PeekMessageW(&msg, nil, 0, 0, PM_REMOVE) != 0 {
            TranslateMessage(&msg); DispatchMessageW(&msg)
        }
    }

    return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
}
```

**Linux X11**
```swift
mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
    switch mode {
    case .wait:
        let event = xcb_wait_for_event(connection)  // Blocking
        translateAndEnqueue(event)

    case .poll:
        while let event = xcb_poll_for_event(connection) {
            translateAndEnqueue(event)
        }

    case .waitUntil(let deadline):
        let fd = xcb_get_file_descriptor(connection)
        let timeoutSec = max(0, deadline.date.timeIntervalSinceNow)
        var timeout = timeval(tv_sec: Int(timeoutSec), tv_usec: 0)
        select(fd + 1, &readSet, nil, nil, &timeout)
        while let event = xcb_poll_for_event(connection) {
            translateAndEnqueue(event)
        }
    }

    return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
}
```

---

### 2.3 Window Decorations & Styles

**Current M0 State**: Standard titled windows only

**New Features**:
- Toggle decorations (borderless windows)
- Always-on-top (floating windows)
- Transparency (alpha channel backgrounds)

#### macOS Implementation

**NSWindow Style Masks**
```swift
extension MacWindow {
    func setDecorated(_ decorated: Bool) {
        if decorated {
            nsWindow.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        } else {
            nsWindow.styleMask = .borderless
        }
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        nsWindow.level = alwaysOnTop ? .floating : .normal
    }

    func setTransparent(_ transparent: Bool) {
        nsWindow.isOpaque = !transparent
        nsWindow.backgroundColor = transparent ? .clear : .windowBackgroundColor
        nsWindow.hasShadow = !transparent  // Optional: disable shadow for transparency
    }
}
```

**Traffic Light Button Control** (macOS-specific)
```swift
func setTrafficLightsVisible(_ visible: Bool) {
    nsWindow.standardWindowButton(.closeButton)?.isHidden = !visible
    nsWindow.standardWindowButton(.miniaturizeButton)?.isHidden = !visible
    nsWindow.standardWindowButton(.zoomButton)?.isHidden = !visible
}
```

#### Windows Implementation

**Window Styles**
```swift
extension WinWindow {
    func setDecorated(_ decorated: Bool) {
        let style = DWORD(decorated ?
            WS_OVERLAPPEDWINDOW :  // Titled, resizable, borders
            WS_POPUP)              // Borderless
        SetWindowLongPtrW(hwnd, GWL_STYLE, LONG_PTR(style))
        SetWindowPos(hwnd, nil, 0, 0, 0, 0,
                     SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER)
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) {
        let hwndInsertAfter = alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST
        SetWindowPos(hwnd, hwndInsertAfter, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE)
    }

    func setTransparent(_ transparent: Bool) {
        if transparent {
            // Enable layered window for per-pixel alpha
            let exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED)
            SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)
        }
    }
}
```

#### Linux X11 Implementation

**EWMH Window State**
```c
// Toggle decorations
xcb_atom_t motif_wm_hints = intern_atom("_MOTIF_WM_HINTS");
struct {
    uint32_t flags = 2;  // MWM_HINTS_DECORATIONS
    uint32_t functions = 0;
    uint32_t decorations = decorated ? 1 : 0;  // 0 = no decorations
    int32_t input_mode = 0;
    uint32_t status = 0;
} hints;
xcb_change_property(connection, XCB_PROP_MODE_REPLACE, window, motif_wm_hints,
                    motif_wm_hints, 32, 5, &hints);

// Always-on-top
xcb_atom_t net_wm_state = intern_atom("_NET_WM_STATE");
xcb_atom_t net_wm_state_above = intern_atom("_NET_WM_STATE_ABOVE");
xcb_change_property(connection, XCB_PROP_MODE_APPEND, window, net_wm_state,
                    XCB_ATOM_ATOM, 32, 1, &net_wm_state_above);
```

#### Linux Wayland Implementation

**xdg-decoration Protocol**
```c
// Request server-side decorations (if available)
struct zxdg_decoration_manager_v1 *decoration_manager = ...; // From registry
struct zxdg_toplevel_decoration_v1 *decoration =
    zxdg_decoration_manager_v1_get_toplevel_decoration(decoration_manager, xdg_toplevel);
zxdg_toplevel_decoration_v1_set_mode(decoration,
    decorated ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE
              : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE);
```

**Transparency**: Wayland supports per-pixel alpha natively via surface format (ARGB8888)

---

### 2.4 Clipboard (Text Only for M1)

**Scope**: UTF-8 text read/write, ownership tracking

#### macOS Implementation (NSPasteboard)

```swift
@MainActor
public struct Clipboard {
    private static var lastChangeCount: Int = 0

    public static func readText() throws -> String? {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        return pasteboard.string(forType: .string)
    }

    public static func writeText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    public static func hasChanged() -> Bool {
        NSPasteboard.general.changeCount != lastChangeCount
    }
}
```

**Thread Safety**: NSPasteboard is main-thread-only → `@MainActor` enforcement

#### Windows Implementation (Clipboard API)

```swift
@MainActor
public struct Clipboard {
    public static func readText() throws -> String? {
        guard OpenClipboard(nil) != 0 else {
            throw LuminaError.clipboardAccessDenied
        }
        defer { CloseClipboard() }

        guard let handle = GetClipboardData(CF_UNICODETEXT) else {
            return nil
        }
        guard let ptr = GlobalLock(handle) else {
            return nil
        }
        defer { GlobalUnlock(handle) }

        return String(decodingCString: ptr.assumingMemoryBound(to: UInt16.self),
                      as: UTF16.self)
    }

    public static func writeText(_ text: String) throws {
        let utf16 = Array(text.utf16) + [0]  // Null-terminated
        let size = utf16.count * 2

        guard let hMem = GlobalAlloc(GMEM_MOVEABLE, SIZE_T(size)) else {
            throw LuminaError.clipboardWriteFailed
        }
        guard let ptr = GlobalLock(hMem) else {
            GlobalFree(hMem)
            throw LuminaError.clipboardWriteFailed
        }
        utf16.withUnsafeBufferPointer { buffer in
            memcpy(ptr, buffer.baseAddress, size)
        }
        GlobalUnlock(hMem)

        guard OpenClipboard(nil) != 0 else {
            GlobalFree(hMem)
            throw LuminaError.clipboardAccessDenied
        }
        defer { CloseClipboard() }

        EmptyClipboard()
        SetClipboardData(CF_UNICODETEXT, hMem)
    }
}
```

**Ownership Tracking**: Poll clipboard sequence number via `GetClipboardSequenceNumber()`

#### Linux X11 Implementation (CLIPBOARD Selection)

```c
// Read text
xcb_atom_t clipboard = intern_atom("CLIPBOARD");
xcb_atom_t utf8_string = intern_atom("UTF8_STRING");

xcb_convert_selection(connection, window, clipboard, utf8_string,
                      XCB_ATOM_PRIMARY, XCB_CURRENT_TIME);
// Wait for SelectionNotify event, read property data

// Write text
xcb_set_selection_owner(connection, window, clipboard, XCB_CURRENT_TIME);
// Respond to SelectionRequest events with text data
```

**Complexity**: X11 clipboard requires event-driven protocol (selection requests/notifications)

**Decision**: Implement synchronous API with internal event handling:
```swift
public static func readText() throws -> String? {
    requestSelection()
    return waitForSelectionNotify(timeout: 1.0)  // Pump events until response
}
```

#### Linux Wayland Implementation (wl_data_device)

```c
// Read text
struct wl_data_offer *offer = ...; // From data_device.data_offer event
wl_data_offer_receive(offer, "text/plain;charset=utf-8", pipe_fd);
// Read from pipe_fd

// Write text
struct wl_data_source *source = wl_data_device_manager_create_data_source(manager);
wl_data_source_offer(source, "text/plain;charset=utf-8");
wl_data_device_set_selection(data_device, source, serial);
// Respond to send events with text data via pipe
```

**Complexity**: Similar event-driven protocol to X11

---

### 2.5 Monitor Enumeration

**Current M0 State**: Basic monitor detection exists for DPI; needs formal API

#### macOS Implementation (NSScreen)

```swift
public struct Monitor: Sendable, Hashable {
    public let id: MonitorID
    public let name: String
    public let position: LogicalPosition      // Top-left corner in global space
    public let size: LogicalSize              // Total dimensions
    public let workArea: LogicalRect          // Usable area (excludes menu bar, dock)
    public let scaleFactor: Float
    public let isPrimary: Bool
}

@MainActor
public func enumerateMonitors() -> [Monitor] {
    NSScreen.screens.map { screen in
        Monitor(
            id: MonitorID(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! Int),
            name: screen.localizedName,
            position: LogicalPosition(
                x: Float(screen.frame.origin.x),
                y: Float(screen.frame.origin.y)  // Convert from bottom-left
            ),
            size: LogicalSize(
                width: Float(screen.frame.width),
                height: Float(screen.frame.height)
            ),
            workArea: LogicalRect(
                origin: LogicalPosition(
                    x: Float(screen.visibleFrame.origin.x),
                    y: Float(screen.visibleFrame.origin.y)
                ),
                size: LogicalSize(
                    width: Float(screen.visibleFrame.width),
                    height: Float(screen.visibleFrame.height)
                )
            ),
            scaleFactor: Float(screen.backingScaleFactor),
            isPrimary: screen == NSScreen.main
        )
    }
}
```

**Change Notifications**
```swift
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { _ in
    eventQueue.append(.monitor(MonitorEvent.configurationChanged))
}
```

#### Windows Implementation (EnumDisplayMonitors)

```swift
public func enumerateMonitors() -> [Monitor] {
    var monitors: [Monitor] = []

    EnumDisplayMonitors(nil, nil, { hMonitor, hdcMonitor, lprcMonitor, dwData in
        var info = MONITORINFOEXW()
        info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
        GetMonitorInfoW(hMonitor, &info)

        var dpiX: UINT = 0, dpiY: UINT = 0
        GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)

        let monitor = Monitor(
            id: MonitorID(Int(bitPattern: hMonitor)),
            name: String(decodingCString: &info.szDevice, as: UTF16.self),
            position: LogicalPosition(x: Float(info.rcMonitor.left), y: Float(info.rcMonitor.top)),
            size: LogicalSize(
                width: Float(info.rcMonitor.right - info.rcMonitor.left),
                height: Float(info.rcMonitor.bottom - info.rcMonitor.top)
            ),
            workArea: LogicalRect(/* info.rcWork */),
            scaleFactor: Float(dpiX) / 96.0,
            isPrimary: (info.dwFlags & MONITORINFOF_PRIMARY) != 0
        )

        monitors.append(monitor)
        return 1  // Continue enumeration
    }, 0)

    return monitors
}
```

**Change Notifications**: Listen for `WM_DISPLAYCHANGE` message

#### Linux X11 Implementation (XRandR)

```c
xcb_randr_get_screen_resources_current_reply_t *resources = ...;
xcb_randr_output_t *outputs = xcb_randr_get_screen_resources_current_outputs(resources);

for (int i = 0; i < resources->num_outputs; i++) {
    xcb_randr_get_output_info_reply_t *output_info =
        xcb_randr_get_output_info_reply(connection,
            xcb_randr_get_output_info(connection, outputs[i], XCB_CURRENT_TIME), NULL);

    if (output_info->connection != XCB_RANDR_CONNECTION_CONNECTED) continue;

    xcb_randr_get_crtc_info_reply_t *crtc_info = ...;
    // Extract position, size, rotation
}
```

**Change Notifications**: Listen for `XCB_RANDR_SCREEN_CHANGE_NOTIFY` event

#### Linux Wayland Implementation (wl_output)

```c
wl_registry_add_listener(registry, &registry_listener, userdata);

// In global_handler:
if (strcmp(interface, wl_output_interface.name) == 0) {
    struct wl_output *output = wl_registry_bind(registry, name, &wl_output_interface, 2);
    wl_output_add_listener(output, &output_listener, userdata);
}

// Output listener callbacks:
void output_geometry(void *data, struct wl_output *output, int32_t x, int32_t y, ...) {
    // Position and physical size
}

void output_mode(void *data, struct wl_output *output, uint32_t flags,
                 int32_t width, int32_t height, int32_t refresh) {
    // Resolution
}

void output_scale(void *data, struct wl_output *output, int32_t factor) {
    // Integer scale factor
}
```

**Change Notifications**: Automatically via wl_output listener callbacks

---

## 3. Cross-Platform Capability System

### 3.1 Runtime Capability Queries

**Requirement FR-033**: Capability groups with per-feature boolean queries

**Design**:
```swift
public struct WindowCapabilities: Sendable {
    public let supportsTransparency: Bool
    public let supportsAlwaysOnTop: Bool
    public let supportsDecorationToggle: Bool
    public let supportsClientSideDecorations: Bool  // Wayland-specific
}

public struct ClipboardCapabilities: Sendable {
    public let supportsText: Bool
    public let supportsImages: Bool  // Future
    public let supportsHTML: Bool    // Future
}

public struct MonitorCapabilities: Sendable {
    public let supportsDynamicRefreshRate: Bool  // ProMotion on macOS
    public let supportsFractionalScaling: Bool
}

extension LuminaWindow {
    func capabilities() -> WindowCapabilities
}

extension Clipboard {
    static func capabilities() -> ClipboardCapabilities
}

public func monitorCapabilities() -> MonitorCapabilities
```

**Platform Matrix**:

| Feature | macOS | Windows | Linux X11 | Linux Wayland |
|---------|-------|---------|-----------|---------------|
| Transparency | ✅ | ✅ | ✅ | ✅ |
| Always-On-Top | ✅ | ✅ | ✅ (EWMH) | ⚠️ (compositor-dependent) |
| Decoration Toggle | ✅ | ✅ | ✅ (Motif hints) | ✅ (xdg-decoration) |
| Client-Side Decorations | N/A | N/A | N/A | ✅ (default) |
| Clipboard Text | ✅ | ✅ | ✅ | ✅ |
| Fractional Scaling | ✅ | ✅ | ⚠️ (Xft.dpi) | ⚠️ (wp_fractional_scale_v1) |

---

## 4. Error Handling Strategy

### 4.1 Typed Error Enum (NFR-008a)

**Current M0 State**: Basic `LuminaError` enum exists

**Extensions for M1**:
```swift
public enum LuminaError: Error, Sendable {
    // Existing M0 errors
    case platformInitializationFailed(String)
    case windowCreationFailed(String)
    case invalidWindowID(WindowID)

    // M1 additions
    case clipboardAccessDenied
    case clipboardReadFailed(String)
    case clipboardWriteFailed(String)
    case monitorEnumerationFailed(String)
    case unsupportedPlatformFeature(feature: String)
    case waylandProtocolMissing(protocol: String)
    case x11ExtensionMissing(extension: String)
}
```

**Throwing vs Result**:
- **Initialization**: `throws` (unrecoverable)
  - `createLuminaApp() throws`
  - `createWindow() throws` (changed from Result for consistency)
- **Clipboard operations**: `throws` (recoverable)
  - `Clipboard.readText() throws -> String?`
  - `Clipboard.writeText(_:) throws`
- **Capability queries**: Non-throwing (always succeed)
  - `window.capabilities() -> WindowCapabilities`

---

## 5. Thread Safety & Concurrency Model (NFR-008)

### 5.1 @MainActor Enforcement

**Current M0 Pattern**: All windowing APIs isolated to `@MainActor`

**M1 Continuation**:
- All `LuminaApp`, `LuminaWindow` methods remain `@MainActor`
- `Clipboard` is `@MainActor` (platform requirement on macOS/Windows)
- Exception: `postUserEvent()` remains `nonisolated` for background thread posting

**Example**:
```swift
@MainActor
public protocol LuminaApp: Sendable {
    mutating func pumpEvents(mode: ControlFlowMode) -> Event?

    nonisolated func postUserEvent(_ event: UserEvent)  // Thread-safe
}
```

**Background Event Posting** (unchanged from M0):
```swift
// From background thread:
Task.detached {
    let result = await heavyComputation()
    app.postUserEvent(UserEvent(result))  // Safe: nonisolated
}

// On main thread:
@MainActor
func processEvents() {
    while let event = app.pumpEvents(mode: .poll) {
        if case .user(let userEvent) = event {
            handleResult(userEvent.data)
        }
    }
}
```

---

## 6. Testing Strategy

### 6.1 Unit Tests (Platform-Independent)

**Scope**: Discrete, logic-only components

**New Tests for M1**:
- `ClipboardTests.swift` - Clipboard text encoding/decoding (mock backend)
- `MonitorTests.swift` - Monitor geometry calculations, coordinate conversions
- `ControlFlowTests.swift` - Deadline calculation, timeout logic
- `CapabilityTests.swift` - Capability struct initialization, query logic
- `ErrorTests.swift` - New error cases, error messages

**Pattern** (from M0):
```swift
import Testing
@testable import Lumina

@Test("Clipboard text encoding")
func testClipboardTextEncoding() {
    let text = "Hello, 世界!"
    let encoded = /* mock encoding */
    let decoded = /* mock decoding */
    #expect(decoded == text)
}
```

---

### 6.2 Platform-Specific Tests

**Requirement NFR-010**: Manual testing on target platforms

**Linux Test Environments**:
- Ubuntu 24.04 LTS (X11 session)
- Ubuntu 24.04 LTS (Wayland session)
- Fedora 40 (Wayland)
- Arch Linux with:
  - GNOME (Mutter compositor)
  - KDE Plasma (KWin compositor)
  - i3 (X11 tiling WM)
  - Sway (Wayland tiling compositor)

**Test Checklist per Platform**:
- [ ] Window creation with title, size constraints
- [ ] Window show/hide/close
- [ ] Window resize (programmatic and user-initiated)
- [ ] Window move (programmatic and user-initiated)
- [ ] Focus events (gained/lost)
- [ ] Mouse move, button press/release, wheel scroll
- [ ] Keyboard input (key down/up, text input, modifiers)
- [ ] Cursor shape changes, visibility toggle
- [ ] DPI scaling (1.0x, 1.5x, 2.0x)
- [ ] Monitor enumeration
- [ ] Clipboard text read/write interop with native apps
- [ ] Window decorations toggle (macOS/Windows only for M1)
- [ ] Transparency (macOS/Windows only for M1)
- [ ] Always-on-top (macOS/Windows only for M1)

**Automation** (future):
- Xvfb (X11 virtual framebuffer) for headless X11 tests
- Weston headless mode for Wayland tests
- Event synthesis with XTest (X11) or uinput (Linux kernel)

---

### 6.3 Integration Tests

**Requirement**: Not mandatory per constitution (NFR-011)

**Optional Future Work**:
- Multi-window application scenarios
- Event ordering validation (golden trace tests)
- Stress tests (100+ windows, 10k events/sec)

---

## 7. Dependencies & Build System

### 7.1 Linux System Dependencies

**Ubuntu/Debian** (apt):
```bash
# X11 backend
sudo apt install libxcb1-dev libxcb-keysyms1-dev libxcb-xkb-dev \
                 libxcb-xinput-dev libxkbcommon-dev libxkbcommon-x11-dev

# Wayland backend
sudo apt install libwayland-dev libxkbcommon-dev libdecor-0-dev

# Optional: XRandR for monitor enumeration
sudo apt install libxcb-randr0-dev
```

**Fedora/RHEL** (dnf):
```bash
# X11
sudo dnf install libxcb-devel libxkbcommon-devel libxkbcommon-x11-devel

# Wayland
sudo dnf install wayland-devel libxkbcommon-devel libdecor-devel
```

**Arch Linux** (pacman):
```bash
sudo pacman -S libxcb libxkbcommon wayland libdecor
```

---

### 7.2 Swift Package Manager Configuration

**Package.swift additions**:
```swift
let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v15),  // macOS 15 (Sequoia) minimum
        .windows(.v11), // Windows 11 minimum
        .linux         // No specific version requirement
    ],
    products: [
        .library(name: "Lumina", targets: ["Lumina"])
    ],
    targets: [
        .target(
            name: "Lumina",
            dependencies: [
                .target(name: "CXCBLinux", condition: .when(platforms: [.linux])),
                .target(name: "CWaylandLinux", condition: .when(platforms: [.linux]))
            ],
            swiftSettings: [
                .define("LUMINA_X11", .when(platforms: [.linux])),
                .define("LUMINA_WAYLAND", .when(platforms: [.linux]))
            ]
        ),

        // System library targets
        .systemLibrary(
            name: "CXCBLinux",
            pkgConfig: "xcb xcb-keysyms xcb-xkb xcb-xinput xkbcommon xkbcommon-x11",
            providers: [
                .apt(["libxcb1-dev", "libxcb-keysyms1-dev", "libxcb-xkb-dev",
                      "libxcb-xinput-dev", "libxkbcommon-dev", "libxkbcommon-x11-dev"])
            ]
        ),
        .systemLibrary(
            name: "CWaylandLinux",
            pkgConfig: "wayland-client xkbcommon",
            providers: [
                .apt(["libwayland-dev", "libxkbcommon-dev"])
            ]
        ),

        .testTarget(
            name: "LuminaTests",
            dependencies: ["Lumina"]
        )
    ]
)
```

**System Library Wrappers**:
- `Sources/CXCBLinux/module.modulemap` - XCB C headers
- `Sources/CWaylandLinux/module.modulemap` - Wayland C headers

---

## 8. Risk Mitigation

### 8.1 Wayland Protocol Fragmentation

**Risk**: Compositors implement different protocol subsets

**Mitigation**:
1. **Core Protocol First**: Implement only `xdg-shell` v2+ (universal support)
2. **Capability Detection**: Check protocol availability via wl_registry
3. **Graceful Degradation**:
   - No `wp_fractional_scale_v1` → use integer scale from wl_output
   - No `xdg-decoration` → use libdecor CSD fallback
4. **Clear Errors**: `LuminaError.waylandProtocolMissing(protocol: "xdg-shell")`
5. **Compositor Testing**: Verify on GNOME, KDE, Sway (covers >90% Wayland users)

---

### 8.2 X11 Window Manager Variations

**Risk**: Inconsistent EWMH compliance (window constraints, decorations)

**Mitigation**:
1. **Lowest-Common-Denominator**: Use universally supported EWMH atoms:
   - `_NET_WM_STATE`, `_NET_WM_NAME` (all WMs)
   - Avoid advanced features like `_NET_WM_STATE_DEMANDS_ATTENTION` (spotty support)
2. **WM Testing**: Verify on:
   - Mutter (GNOME) - full EWMH
   - KWin (KDE Plasma) - full EWMH
   - i3 (tiling WM) - partial EWMH
   - Openbox (stacking WM) - partial EWMH
3. **Compatibility Matrix Documentation**: Document known quirks (e.g., i3 ignores min/max size)
4. **Fallback Behavior**: If WM ignores hints, application adapts (e.g., enforce size constraints in app logic)

---

### 8.3 DPI Scaling Inconsistencies (Linux)

**Risk**: X11 DPI detection unreliable, mixed-DPI setups broken

**Mitigation**:
1. **Priority-Based Detection**:
   ```
   1. XSETTINGS daemon (Xft/DPI) - most reliable if available
   2. Xft.dpi resource (~/.Xresources) - user-configured
   3. Physical dimensions (screen width_in_millimeters) - calculated fallback
   4. 96 DPI default - safe fallback
   ```
2. **Manual Override API** (future):
   ```swift
   window.setScaleFactor(2.0)  // Application-controlled DPI
   ```
3. **Mixed-DPI Testing**: Test with 1x + 2x monitor setup on X11
4. **Wayland Advantage**: Wayland has reliable per-output scale factor

---

### 8.4 Thread Safety Violations (macOS/Windows)

**Risk**: AppKit/Win32 main-thread-only requirement violated

**Mitigation**:
1. **Compile-Time Enforcement**: `@MainActor` on all windowing APIs
2. **Runtime Checks** (debug builds):
   ```swift
   precondition(Thread.isMainThread, "Must be called on main thread")
   ```
3. **NSLock Protection**: User event queues protected with locks (M0 pattern)
4. **Clear Documentation**: API docs state thread requirements
5. **Example Code**: All examples demonstrate correct threading

---

## 9. Performance Targets (from NFR-001, NFR-002)

### 9.1 Event Latency: < 1ms

**Measurement**:
- Timestamp event at OS level (NSEvent.timestamp, GetMessageTime())
- Compare to Lumina Event receipt timestamp
- Target: p99 < 1ms on reference hardware

**Optimization Strategies**:
- Zero-copy event translation (stack-allocated structs)
- Minimal allocations in event loop
- Lock-free user event queue (M0 uses NSLock - revisit if bottleneck)

**Reference Hardware**: MacBook Pro M1, 2021 Windows laptop (Intel i7)

---

### 9.2 Idle CPU Usage: < 0.1%

**Measurement**:
- Run application with event loop in Wait mode
- No user interaction for 60 seconds
- Measure CPU % with Activity Monitor / Task Manager

**Current M0 Status**: Passes (uses blocking NSApp.nextEvent / GetMessageW)

**M1 Verification**: Ensure X11/Wayland blocking also meets target
- X11: `xcb_wait_for_event()` blocks without spin
- Wayland: `wl_display_dispatch()` blocks on fd read

---

## 10. Key Design Decisions Summary

| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| **XCB over Xlib** | Better async, thread-safe, cleaner Swift bindings | Xlib (legacy, not thread-safe) |
| **libdecor for Wayland CSD** | Theme consistency, minimal code | Custom decorations (too much work), xdg-decoration only (limited support) |
| **Environment-based backend detection** | Matches user session type | Explicit API (future enhancement) |
| **Hybrid redraw strategy (NSView + CADisplayLink)** | Covers system and app-initiated redraws | Pure CADisplayLink (misses system events), Pure NSView (no frame pacing) |
| **Unified ControlFlowMode enum** | Consistent cross-platform API | Per-platform methods (fragments API) |
| **Synchronous clipboard API** | Simpler for developers | Async API (complexity not justified for M1 text-only) |
| **wl_shm (software rendering)** | Simple, sufficient for windowing | Vulkan/GPU buffers (deferred to graphics milestone) |
| **@MainActor enforcement** | Compile-time safety | Runtime checks only (catch errors late) |
| **Swift Testing only** | Modern, async-aware, consistent | XCTest (legacy, less capable) |

---

## 11. Open Questions & Future Work

### 11.1 Deferred to M2+

- **Fullscreen Mode**: Exclusive and borderless variants
- **IME Support**: Composition events for CJK input
- **Custom Cursors**: Image-based cursors beyond system set
- **Drag-and-Drop**: File/data drag between windows
- **Multi-Touch Gestures**: Pinch, rotate, swipe on trackpads
- **Game Controller Input**: Joystick/gamepad APIs
- **High-DPI Icons**: Automatic icon scaling on Wayland/X11
- **Raw Input Mode**: Unbuffered, low-latency input for games

### 11.2 Performance Tuning (M2+)

- **Event Batching**: Group rapid events (mouse move) into single delivery
- **Lock-Free Queues**: Replace NSLock with atomics for user event queue
- **SIMD Coordinate Conversion**: Vectorize LogicalSize → PhysicalSize
- **Memory Pooling**: Reuse event allocations

### 11.3 Platform-Specific Enhancements (M3+)

- **macOS**: Metal layer integration, Touch Bar support, Notification Center
- **Windows**: DirectX swap chain, touch events, Windows 11 Snap Layouts
- **Linux**: Vulkan WSI integration, Fractional scaling (wp_fractional_scale_v1), Portal APIs (file picker)

---

## 12. Success Criteria Validation

| Criterion | M1 Achievement |
|-----------|----------------|
| **Cross-Platform Parity (Wave A)** | ✅ Linux (X11 + Wayland) implements all M0 features |
| **macOS Wave B Foundation** | ✅ Redraw, control flow, decorations, clipboard, monitors |
| **Developer Experience** | ✅ < 10 min setup (apt install + swift build on Ubuntu) |
| **Quality** | ✅ Zero P0 bugs, manual checklist complete |
| **Documentation** | ✅ API docs, platform matrix, examples |
| **Linux User Readiness** | ✅ Experimental use possible (0.2.x version) |

---

## 13. References

**X11/XCB**:
- [XCB Documentation](https://xcb.freedesktop.org/) - Core protocol reference
- [EWMH Spec](https://specifications.freedesktop.org/wm-spec/wm-spec-latest.html) - Window manager hints
- [XKB Documentation](https://www.x.org/releases/X11R7.6/doc/kbproto/xkbproto.html) - Keyboard extension

**Wayland**:
- [Wayland Protocol Spec](https://wayland.freedesktop.org/docs/html/) - Core protocols
- [xdg-shell Protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml) - Window management
- [libdecor Documentation](https://gitlab.freedesktop.org/libdecor/libdecor) - Client-side decorations

**macOS**:
- [NSWindow Class Reference](https://developer.apple.com/documentation/appkit/nswindow) - Window management
- [NSScreen Class Reference](https://developer.apple.com/documentation/appkit/nsscreen) - Monitor enumeration
- [NSPasteboard Class Reference](https://developer.apple.com/documentation/appkit/nspasteboard) - Clipboard

**Windows**:
- [Windows API Index](https://learn.microsoft.com/en-us/windows/win32/apiindex/windows-api-list) - Win32 reference
- [DPI Awareness](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows) - Scaling guide

**Swift**:
- [Swift 6.2 Release Notes](https://www.swift.org/blog/swift-6-2-released/) - New features
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html) - @MainActor, Sendable

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
**Research Status**: ✅ Complete - Ready for Phase 1 Design
