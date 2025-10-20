# Tasks: Milestone 1 - Linux Support & macOS Wave B

**Input**: Design documents from `/Users/alexander/dev/apple/Lumina/specs/002-milestone-1-impl/`
**Prerequisites**: plan.md, design.md, research.md (all complete)
**Branch**: `002-milestone-1-impl`

---

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no shared dependencies)
- All paths are relative to repository root: `/Users/alexander/dev/apple/Lumina/`

---

## Phase 1: Core Type Extensions (Foundation Layer)

### Event System Extensions
- [X] **T001** [P] Extend Event enum with RedrawEvent and MonitorEvent cases in `Sources/Lumina/Core/Events.swift`
  - Add `case redraw(RedrawEvent)` and `case monitor(MonitorEvent)`
  - Implement RedrawEvent enum: `case requested(WindowID, dirtyRect: LogicalRect?)`
  - Implement MonitorEvent enum: `case configurationChanged`
  - Ensure Sendable and Hashable conformance
  - Add pattern matching support for new event types

### Control Flow & Geometry
- [X] **T002** [P] Create ControlFlowMode enum in new file `Sources/Lumina/Core/ControlFlowMode.swift`
  - Implement enum: `case wait`, `case poll`, `case waitUntil(Deadline)`
  - Implement `Deadline` struct with `init(seconds:)` and `init(date:)`
  - Add `hasExpired` computed property
  - Mark all types as Sendable

- [X] **T003** [P] Extend Monitor with full API in `Sources/Lumina/Core/Monitor.swift`
  - Keep existing MonitorID struct
  - Add LogicalRect struct: `init(origin: LogicalPosition, size: LogicalSize)`
  - Extend Monitor struct with full properties: id, name, position, size, workArea, scaleFactor, isPrimary
  - Add global functions: `enumerateMonitors() throws -> [Monitor]` and `primaryMonitor() throws -> Monitor`
  - Mark as @MainActor
  - Ensure Sendable and Hashable conformance

### Capabilities System
- [X] **T004** [P] Create Capabilities types in new file `Sources/Lumina/Core/Capabilities.swift`
  - Implement WindowCapabilities struct: supportsTransparency, supportsAlwaysOnTop, supportsDecorationToggle, supportsClientSideDecorations
  - Implement ClipboardCapabilities struct: supportsText, supportsImages, supportsHTML
  - Implement MonitorCapabilities struct: supportsDynamicRefreshRate, supportsFractionalScaling
  - All structs Sendable and Hashable with initializers

### Clipboard & Error Handling
- [X] **T005** [P] Create Clipboard API in new file `Sources/Lumina/Core/Clipboard.swift`
  - Mark struct as @MainActor and Sendable
  - Add static methods: `readText() throws -> String?`, `writeText(_ text: String) throws`, `hasChanged() -> Bool`
  - Add platform-specific implementations via conditional compilation hooks

- [X] **T006** [P] Extend LuminaError enum in `Sources/Lumina/Core/Errors.swift`
  - Add clipboard errors: clipboardAccessDenied, clipboardReadFailed(String), clipboardWriteFailed(String)
  - Add monitor errors: monitorEnumerationFailed(String)
  - Add platform errors: unsupportedPlatformFeature(feature: String), waylandProtocolMissing(protocol: String), x11ExtensionMissing(extension: String)
  - Extend CustomStringConvertible with new error descriptions

### Protocol Extensions
- [X] **T007** Extend LuminaApp protocol in `Sources/Lumina/Core/LuminaApp.swift`
  - Add `pumpEvents(mode: ControlFlowMode) -> Event?` method
  - Add static methods: `monitorCapabilities() -> MonitorCapabilities`, `clipboardCapabilities() -> ClipboardCapabilities`
  - Update default implementations: `run()`, `poll()`, `wait()` to use pumpEvents()
  - Maintain @MainActor isolation

- [X] **T008** Extend LuminaWindow protocol in `Sources/Lumina/Core/LuminaWindow.swift`
  - Add Wave B methods: `requestRedraw()`, `setDecorated(_ decorated: Bool) throws`, `setAlwaysOnTop(_ alwaysOnTop: Bool) throws`, `setTransparent(_ transparent: Bool) throws`
  - Add `capabilities() -> WindowCapabilities` and `currentMonitor() throws -> Monitor`
  - Provide default implementations that throw unsupportedPlatformFeature for platforms without Wave B

- [X] **T008a** Refactor Cursor to protocol-based pattern in `Sources/Lumina/Core/Cursor.swift`
  - Create `@MainActor public protocol LuminaCursor: Sendable` with instance methods
  - Add methods: `func set(_ cursor: SystemCursor)`, `func hide()`, `func show()`
  - Keep SystemCursor enum unchanged (maintained from M0)
  - Update LuminaWindow protocol to add `func cursor() -> any LuminaCursor`
  - Remove static API pattern (breaking change from M0, justified by architectural consistency)
  - Update all platform implementations (MacWindow, WinWindow) to return platform-specific cursor instances
  - Document migration path in API documentation: `Cursor.set(.hand)` → `window.cursor().set(.hand)`

---

## Phase 2: macOS Wave B Implementation

### MacApplication Enhancements
- [X] **T009** Extend MacApplication in `Sources/Lumina/Platforms/macOS/MacApplication.swift`
  - Add state properties: `redrawRequests: Set<WindowID>`, `displayLink: CADisplayLink?`, `lastChangeCount: Int`
  - Implement `pumpEvents(mode: ControlFlowMode) -> Event?` with NSRunLoop integration (wait/poll/waitUntil timeout logic)
  - Add `markWindowNeedsRedraw(_ windowID: WindowID)` helper
  - Implement static capability methods: `monitorCapabilities()` (ProMotion support), `clipboardCapabilities()` (text only)
  - Process redraw requests with priority in event pump

### MacWindow Wave B Methods
- [X] **T010** Extend MacWindow in `Sources/Lumina/Platforms/macOS/MacWindow.swift`
  - Implement `requestRedraw()` using `setNeedsDisplay()` and application.markWindowNeedsRedraw()
  - Implement `setDecorated(_ decorated: Bool)` with NSWindow styleMask manipulation (titled/borderless)
  - Implement `setAlwaysOnTop(_ alwaysOnTop: Bool)` using window.level (.floating/.normal)
  - Implement `setTransparent(_ transparent: Bool)` with isOpaque, backgroundColor, hasShadow
  - Implement `capabilities()` returning full WindowCapabilities (all true except CSD)
  - Implement `currentMonitor()` returning Monitor from window.screen

### macOS Monitor Support
- [X] **T011** Extend MacMonitor in `Sources/Lumina/Platforms/macOS/MacMonitor.swift`
  - Implement `fromNSScreen(_ screen: NSScreen) throws -> Monitor` static method
  - Convert AppKit bottom-left coordinates to top-left
  - Extract screen number, localizedName, frame, visibleFrame, backingScaleFactor
  - Implement global `enumerateMonitors()` using NSScreen.screens
  - Add monitor change notifications using NSApplication.didChangeScreenParametersNotification

### macOS Clipboard Implementation
- [X] **T012** [P] Create MacClipboard in new file `Sources/Lumina/Platforms/macOS/MacClipboard.swift`
  - Mark struct as @MainActor
  - Implement `readText()` using NSPasteboard.general.string(forType: .string)
  - Implement `writeText()` using clearContents() and setString()
  - Implement `hasChanged()` tracking NSPasteboard.changeCount
  - Wire to global Clipboard API via conditional compilation (#if os(macOS))

### macOS Capabilities
- [X] **T013** [P] Capability methods implemented in MacApplication, MacWindow, and MacClipboard
  - Implemented capability queries for macOS Wave B features
  - Documented macOS-specific behaviors (integer scaling, no CSD)

---

## Phase 3: Linux X11 Implementation

### C Interop Setup
- [X] **T014** [P] Create CXCBLinux module in `Sources/CInterop/CXCBLinux/`
  - Create `module.modulemap` with headers for xcb, xcb-keysyms, xcb-xkb, xcb-xinput, xkbcommon, xkbcommon-x11
  - Create `shims.h` with C helper functions for XCB API
  - Add link directives for all XCB libraries
  - Document required system packages (libxcb-dev, etc.)

### X11 Atoms & Core Types
- [X] **T015** Create X11Atoms in new file `Sources/Lumina/Platforms/Linux/X11/X11Atoms.swift`
  - Define X11Atoms struct with cached atom IDs: WM_PROTOCOLS, WM_DELETE_WINDOW, _NET_WM_NAME, _NET_WM_STATE, _NET_WM_STATE_ABOVE, _NET_WM_STATE_FULLSCREEN, _MOTIF_WM_HINTS, CLIPBOARD, UTF8_STRING
  - Implement `static func cache(connection:) throws -> X11Atoms` using xcb_intern_atom
  - Error handling for missing atoms

### X11Application Event Loop
- [X] **T016** Create X11Application in new file `Sources/Lumina/Platforms/Linux/X11/X11Application.swift`
  - Mark as @MainActor conforming to LuminaApp
  - Implement init() with XCB connection, screen, XKB context setup
  - Add state: connection, screen, atoms, xkbContext, eventQueue, userEventQueue, windowRegistry
  - Implement `pumpEvents(mode:)` with xcb_wait_for_event (wait), xcb_poll_for_event (poll), select() with timeout (waitUntil)
  - Implement `translateAndEnqueueXCBEvent()` for XCB_EXPOSE, XCB_CONFIGURE_NOTIFY, XCB_BUTTON_PRESS/RELEASE, XCB_MOTION_NOTIFY, XCB_KEY_PRESS/RELEASE, XCB_CLIENT_MESSAGE
  - Implement thread-safe `postUserEvent()` with dummy event wake mechanism
  - Implement `createWindow()` delegating to X11Window
  - Implement static capability methods

### X11Window Implementation
- [X] **T017** Create X11Window in new file `Sources/Lumina/Platforms/Linux/X11/X11Window.swift`
  - Mark as @MainActor conforming to LuminaWindow
  - Implement `static func create()` with xcb_generate_id, xcb_create_window, event mask setup, WM_PROTOCOLS
  - Implement show/hide/close with xcb_map_window, xcb_unmap_window, xcb_destroy_window
  - Implement setTitle with xcb_change_property (_NET_WM_NAME)
  - Implement size/resize/position/moveTo with XCB geometry queries
  - Implement requestRedraw() with xcb_clear_area (force expose)
  - Implement setDecorated() using _MOTIF_WM_HINTS
  - Implement setAlwaysOnTop() using _NET_WM_STATE_ABOVE
  - Implement setTransparent() throwing unsupportedPlatformFeature (requires ARGB visual)
  - Implement capabilities() returning platform-specific WindowCapabilities

### X11 Input Translation
- [X] **T018** [P] Create X11Input in new file `Sources/Lumina/Platforms/Linux/X11/X11Input.swift`
  - Implement static translation functions for XCB events to Lumina events
  - `translateButtonEvent()` for mouse buttons
  - `translateMotionEvent()` for mouse movement
  - `translateKeyEvent()` with XKB keymap interpretation
  - `translateScrollEvent()` for wheel events
  - Coordinate conversions (X11 uses top-left natively)
  - Modifier key mapping (Shift, Control, Alt, Super)

### X11 Monitor Enumeration
- [X] **T019** [P] Create X11Monitor in new file `Sources/Lumina/Platforms/Linux/X11/X11Monitor.swift`
  - Implement monitor enumeration using XRandR (xcb_randr_get_screen_resources_current)
  - Parse output info: position, size, rotation, connection status
  - Implement DPI detection: XSETTINGS → Xft.dpi → physical dimensions → 96 DPI fallback
  - Subscribe to XCB_RANDR_SCREEN_CHANGE_NOTIFY for configuration changes
  - Convert to Monitor structs with proper scale factor calculation

### X11 Clipboard
- [X] **T020** [P] Create X11Clipboard in new file `Sources/Lumina/Platforms/Linux/X11/X11Clipboard.swift`
  - Implement CLIPBOARD selection protocol with xcb_convert_selection for read
  - Implement xcb_set_selection_owner for write
  - Handle SelectionNotify and SelectionRequest events
  - Provide synchronous API with internal event pumping (timeout 1.0s)
  - UTF-8 text encoding/decoding
  - Wire to global Clipboard API via conditional compilation

### X11 Capabilities
- [X] **T021** [P] Create X11Capabilities in new file `Sources/Lumina/Platforms/Linux/X11/X11Capabilities.swift`
  - Implement runtime X11 capability detection
  - Check for EWMH support, XInput2, XRandR versions
  - Document window manager compatibility matrix

---

## Phase 4: Linux Wayland Implementation

### C Interop Setup
- [ ] **T022** [P] Create CWaylandLinux module in `Sources/CInterop/CWaylandLinux/`
  - Create `module.modulemap` with headers for wayland-client, xkbcommon
  - Create `shims.h` with Wayland helper functions
  - Add link directives for wayland-client, xkbcommon
  - Document required system packages (libwayland-dev, etc.)

### Wayland Protocols & Core Types
- [ ] **T023** Create WaylandProtocols in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandProtocols.swift`
  - Define WaylandProtocols struct tracking available protocols: hasFractionalScale, hasXdgDecoration, versions
  - Track essential protocols (xdg-shell) and optional protocols (fractional-scale, xdg-decoration)
  - Implement protocol enumeration via wl_registry listener callbacks
  - Runtime capability detection for optional protocols

### WaylandApplication Event Loop
- [ ] **T024** Create WaylandApplication in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandApplication.swift`
  - Mark as @MainActor conforming to LuminaApp
  - Implement init() with wl_display_connect, registry binding, protocol enumeration
  - Bind essential protocols: wl_compositor, xdg_wm_base, wl_seat
  - Add state: display, compositor, wmBase, seat, protocols, eventQueue, userEventQueue, windowRegistry
  - Implement `pumpEvents(mode:)` with wl_display_dispatch (wait), wl_display_dispatch_pending (poll), select() with fd (waitUntil)
  - Implement thread-safe `postUserEvent()`
  - Implement `createWindow()` delegating to WaylandWindow
  - Implement static capability methods
  - Error on missing essential protocols (xdg-shell v2+)

### WaylandWindow Implementation
- [ ] **T025** Create WaylandWindow in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandWindow.swift`
  - Mark as @MainActor conforming to LuminaWindow
  - Implement `static func create()` with wl_compositor_create_surface, xdg_wm_base_get_xdg_surface, xdg_surface_get_toplevel
  - Configure xdg_toplevel: set_title, set_min_size, set_max_size
  - Implement show/hide/close with surface lifecycle
  - Implement setTitle with xdg_toplevel_set_title
  - Implement requestRedraw() with wl_surface_damage and wl_surface_commit
  - Implement setDecorated() throwing unsupportedPlatformFeature (requires xdg-decoration protocol)
  - Implement setAlwaysOnTop() throwing unsupportedPlatformFeature (no standard protocol)
  - Implement setTransparent() with ARGB8888 surface format
  - Implement capabilities() returning platform-specific WindowCapabilities (transparency supported, CSD true)

### Wayland Input Translation
- [ ] **T026** [P] Create WaylandInput in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandInput.swift`
  - Implement wl_pointer listener for mouse events: enter, leave, motion, button
  - Implement wl_keyboard listener for keyboard events: keymap, key, modifiers
  - Integrate libxkbcommon for keymap interpretation
  - Translate Wayland events to Lumina Event types
  - Handle wl_seat capability detection (pointer, keyboard, touch)

### Wayland Monitor Enumeration
- [ ] **T027** [P] Create WaylandMonitor in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandMonitor.swift`
  - Implement wl_output listener: geometry, mode, scale, done callbacks
  - Track output configuration: position, resolution, scale factor
  - Handle fractional scaling via wp_fractional_scale_v1 if available
  - Convert to Monitor structs
  - Subscribe to output configuration changes automatically via listeners

### Wayland Clipboard
- [ ] **T028** [P] Create WaylandClipboard in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandClipboard.swift`
  - Implement wl_data_device_manager protocol for clipboard
  - Implement read via wl_data_offer with MIME type negotiation (text/plain;charset=utf-8)
  - Implement write via wl_data_source with pipe-based data transfer
  - Handle selection events and data transfer callbacks
  - Wire to global Clipboard API via conditional compilation

### Wayland Capabilities
- [ ] **T029** [P] Create WaylandCapabilities in new file `Sources/Lumina/Platforms/Linux/Wayland/WaylandCapabilities.swift`
  - Implement compositor capability detection from WaylandProtocols
  - Document compositor compatibility (GNOME, KDE Plasma, Sway, Weston)
  - Provide feature availability queries

---

## Phase 5: Linux Backend Selection

- [ ] **T030** Create LinuxApplication in new file `Sources/Lumina/Platforms/Linux/LinuxApplication.swift`
  - Implement `createLuminaApp()` factory function for Linux
  - Environment-based detection: WAYLAND_DISPLAY → try WaylandApplication, fallback to X11
  - DISPLAY → X11Application
  - Error if no display server detected
  - Mark with #if os(Linux) conditional compilation

---

## Phase 5.5: Logging Infrastructure (swift-log Integration)

- [ ] **T030a** Add swift-log dependency in Package.swift
  - Add `.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")` to dependencies
  - Add "Logging" product dependency to Lumina target
  - Ensure compatible with Swift 6.2+ concurrency model

- [ ] **T030b** Create Logger infrastructure in new file `Sources/Lumina/Core/Logging.swift`
  - Import Logging framework
  - Create `public struct LuminaLogger` wrapping Logger
  - Add configurable log levels: off, error, info, debug, trace (per NFR-005)
  - Add convenience methods: `logEvent(_:)`, `logStateTransition(_:)`, `logPlatformCall(_:)`, `logCapabilityDetection(_:)`, `logError(_:)`
  - Include high-resolution timestamps (per NFR-007)
  - Mark as Sendable for cross-thread logging

- [ ] **T030c** Integrate logging in platform implementations
  - Add logger property to MacApplication, X11Application, WaylandApplication
  - Log events: window creation, focus changes, scale factor changes (per NFR-006)
  - Log state transitions: event loop mode switches, window lifecycle
  - Log platform-specific calls: XCB operations, Wayland protocol calls, AppKit interactions
  - Log capability detection: X11 extensions, Wayland protocols, macOS feature availability
  - Log error conditions: missing protocols, failed operations
  - Use appropriate log levels (debug for verbose, info for state changes, error for failures)

---

## Phase 6: Testing (Pure Logic Only)

### Unit Tests - Core Types
- [ ] **T031** [P] Extend EventTests in `Tests/LuminaTests/Core/EventTests.swift`
  - Test RedrawEvent enum: pattern matching, equality, hashing
  - Test MonitorEvent enum: pattern matching, equality
  - Test Event enum with new cases
  - Verify Sendable conformance

- [ ] **T032** [P] Create ControlFlowTests in new file `Tests/LuminaTests/Core/ControlFlowTests.swift`
  - Test Deadline creation: init(seconds:), init(date:)
  - Test hasExpired logic with Thread.sleep()
  - Test ControlFlowMode enum cases
  - Verify Sendable conformance

- [ ] **T033** [P] Create MonitorStructTests in new file `Tests/LuminaTests/Core/MonitorStructTests.swift`
  - Test Monitor struct initialization
  - Test value type semantics (equality, copying)
  - Test Hashable conformance
  - Test LogicalRect initialization and properties
  - NO system calls - pure value type testing only

- [ ] **T034** [P] Create CapabilitiesTests in new file `Tests/LuminaTests/Core/CapabilitiesTests.swift`
  - Test WindowCapabilities equality and hashing
  - Test ClipboardCapabilities equality and hashing
  - Test MonitorCapabilities equality and hashing
  - Test struct initialization with all combinations

- [ ] **T035** [P] Extend ErrorTests in `Tests/LuminaTests/Core/ErrorTests.swift`
  - Test new error cases: clipboard errors, monitor errors, platform feature errors
  - Test CustomStringConvertible descriptions
  - Verify error equality

---

## Phase 7: Manual Testing Checklists

### macOS Manual Tests
- [ ] **T036** [P] Create macOS Wave B checklist in new file `Tests/Manual/macOS/macos-wave-b-checklist.md`
  - RedrawRequested event testing (manual trigger, system trigger)
  - Control flow modes (wait, poll, waitUntil with various timeouts)
  - Window decorations toggle (bordered ↔ borderless)
  - Always-on-top behavior
  - Window transparency with alpha backgrounds
  - Clipboard text operations (copy to/from TextEdit, UTF-8 with emoji)
  - Monitor enumeration and configuration change events
  - Verify on macOS 15+ (Sequoia)

- [ ] **T037** [P] Create macOS regression checklist in new file `Tests/Manual/macOS/macos-wave-a-regression.md`
  - Verify all M0 features still work: window creation, input events, DPI scaling, cursor management
  - Ensure backward compatibility with existing M0 applications

### Linux Manual Tests
- [ ] **T038** [P] Create X11 checklist in new file `Tests/Manual/Linux/linux-x11-checklist.md`
  - Window creation, show/hide, title, resize constraints
  - Mouse events (move, buttons, scroll)
  - Keyboard events (keys, modifiers, text input - Latin only)
  - Cursor shapes and visibility
  - DPI detection (1.0x, 1.5x, 2.0x via Xft.dpi)
  - Monitor enumeration
  - Clipboard interop with gedit/Kate
  - Window decorations toggle
  - Always-on-top
  - Test on Ubuntu 24.04 X11, Fedora 40, Arch with GNOME/KDE/i3

- [ ] **T039** [P] Create Wayland checklist in new file `Tests/Manual/Linux/linux-wayland-checklist.md`
  - Window creation with xdg-shell protocol
  - Input events via wl_pointer, wl_keyboard
  - DPI scaling (integer and fractional if available)
  - Monitor enumeration via wl_output
  - Clipboard interop
  - Window transparency
  - Verify compositor compatibility: GNOME Wayland, KDE Plasma, Sway
  - Document missing features (always-on-top, decoration toggle)
  - Test on Ubuntu 24.04 Wayland, Fedora 40

- [ ] **T040** [P] Create DPI scenarios in new file `Tests/Manual/Linux/linux-dpi-scenarios.md`
  - Single monitor at 1.0x, 1.5x, 2.0x scale
  - Mixed-DPI setup (1.0x + 2.0x monitors)
  - Move window between monitors with different scales
  - Verify scale change events
  - Test on both X11 and Wayland

### Windows Regression Tests
- [ ] **T041** [P] Create Windows regression checklist in new file `Tests/Manual/Windows/windows-regression.md`
  - Verify all M0 features still work on Windows 11
  - Ensure no regressions from M1 core type changes

---

## Phase 8: Package Configuration

- [ ] **T042** Update Package.swift with Linux system library targets and swift-log
  - Set minimum Swift version: `.swiftLanguageVersions([.v6])`
  - Set platforms: `.macOS(.v15), .windows(.v11), .linux`
  - Add swift-log dependency: `.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")`
  - Add CXCBLinux .systemLibrary target with pkgConfig and apt/yum providers
  - Add CWaylandLinux .systemLibrary target
  - Add conditional dependencies for Linux platform
  - Define LUMINA_X11 and LUMINA_WAYLAND compiler flags for Linux
  - Add "Logging" product to Lumina target dependencies

---

## Phase 9: Documentation & Polish

- [ ] **T043** [P] Document new APIs in source files
  - Add API documentation for all protocol extensions (pumpEvents, Wave B methods)
  - Document ControlFlowMode, Deadline, Capabilities structs with examples
  - Document Clipboard API with usage examples
  - Document Monitor API with enumeration examples
  - Document LuminaLogger API with configuration and usage examples
  - Follow Constitution Principle I: descriptions, parameters, return values, throws, AND usage examples for every public API

- [ ] **T044** [P] Create platform compatibility matrix in `docs/platform-compatibility.md`
  - Create feature support matrix (macOS, Windows, Linux X11, Linux Wayland)
  - Document platform-specific limitations (X11 transparency, Wayland always-on-top, etc.)
  - Add notes for each partial support (⚠️) entry
  - Reference from README

- [ ] **T045** [P] Update README.md with Linux build instructions
  - Add Linux dependencies installation (apt, dnf, pacman)
  - Document build process: swift build, swift test
  - Add quick start example for all platforms
  - Update supported platforms list

- [ ] **T046** [P] Create example applications in `Examples/`
  - HelloWindow: Basic window creation on all platforms
  - InputExplorer: Demonstrates all Wave A input types
  - ScalingDemo: Visualizes DPI changes and mixed-DPI scenarios
  - ClipboardText: macOS Wave B clipboard example
  - FramePacing: macOS Wave B animation with control flow modes

---

## Phase 10: Final Validation

- [ ] **T047** Run full test suite on all platforms
  - macOS: swift test (unit tests pass)
  - Linux X11: swift test in Xvfb (future automation)
  - Linux Wayland: swift test in Weston headless (future automation)
  - Windows: swift test (regression verification)
  - Verify all unit tests pass, no broken states

- [ ] **T048** Execute all manual testing checklists
  - Complete T036 (macOS Wave B)
  - Complete T037 (macOS regression)
  - Complete T038 (Linux X11)
  - Complete T039 (Linux Wayland)
  - Complete T040 (Linux DPI scenarios)
  - Complete T041 (Windows regression)
  - Document results and any platform-specific issues discovered

- [ ] **T049** Performance validation
  - Measure event latency on all platforms (target < 1ms)
  - Measure idle CPU usage in Wait mode (target < 0.1%)
  - Measure frame pacing on macOS (60 fps with CADisplayLink)
  - Profile memory usage with 100 concurrent windows
  - Document performance results

- [ ] **T050** Verify locally before PR
  - All platforms compile without errors or warnings
  - All unit tests pass
  - All examples build and run successfully
  - Documentation builds without errors
  - No P0 or P1 bugs identified
  - Constitution compliance verified (all 6 principles)
  - Verify M0 cursor APIs (FR-027-030) unchanged and functional
  - Verify logging output at all configured levels (off/error/info/debug/trace)

---

## Dependencies

**Critical Path**:
1. T001-T008a (Core types and protocol extensions) must complete before any platform implementation
2. T007-T008a (Protocol extensions) block all platform implementations
3. macOS Wave B (T009-T013): Sequential within group
4. X11 (T014-T021): T015 (atoms) blocks T016 (application), T016 blocks T017 (window)
5. Wayland (T022-T029): T023 (protocols) blocks T024 (application), T024 blocks T025 (window)
6. T030 (LinuxApplication) requires T016 (X11Application) and T024 (WaylandApplication)
7. T030a-T030c (Logging infrastructure) must complete before T031 (testing phase)
8. T042 (Package.swift) requires T014 (CXCBLinux), T022 (CWaylandLinux), and T030a (swift-log dependency)
9. Testing (T031-T041) can start after T001-T008a and T030a-T030c complete
10. Documentation (T043-T046) can run in parallel with testing
11. Final validation (T047-T050) requires ALL previous tasks complete

**Parallel Groups**:
- **Group 1** [P]: T001, T002, T003, T004, T005, T006 (core types, different files)
- **Group 2** [P]: T012, T013, T014, T022 (platform-specific setup, different files)
- **Group 3** [P]: T018, T019, T020, T021 (X11 subsystems, different files)
- **Group 4** [P]: T026, T027, T028, T029 (Wayland subsystems, different files)
- **Group 5** [P]: T031, T032, T033, T034, T035 (unit tests, different files)
- **Group 6** [P]: T036, T037, T038, T039, T040, T041 (manual test checklists, different files)
- **Group 7** [P]: T043, T044, T045, T046 (documentation, different files)

Note: T030a-T030c (Logging) are sequential: T030a → T030b → T030c

---

## Validation Checklist

- [x] All protocol extensions have tasks (LuminaApp, LuminaWindow)
- [x] All new core types have implementation tasks (Events, ControlFlowMode, Monitor, Capabilities, Clipboard, Logging)
- [x] All platform implementations have tasks (macOS Wave B, X11, Wayland)
- [x] All tests use Swift Testing framework (NO XCTest)
- [x] Tests come AFTER implementation (unit tests for logic, manual tests for platform)
- [x] Pre-submission verification task included (T050)
- [x] Parallel tasks are truly independent (different files)
- [x] Each task specifies exact file path
- [x] Constitution compliance verification included (T050)
- [x] All NFRs have corresponding tasks (including NFR-005-007 logging via swift-log)

---

## Notes

- **Swift Testing Only**: All unit tests use Swift Testing framework (XCTest prohibited per constitution)
- **Manual Testing**: Clipboard and monitor operations are platform-dependent and tested manually
- **Implementation First**: Tasks follow implementation-first approach (no TDD per constitution)
- **Incremental Commits**: Commit after each task completion to maintain working states
- **Platform Isolation**: Use #if os(Linux) / #if os(macOS) for platform-specific code
- **Performance Critical**: Event loop is hot path - optimize with zero-copy, atom caching, inline functions
- **Borrowing Ownership**: Use `consuming func close()` pattern, value types where possible
- **@MainActor**: All windowing APIs isolated to main actor for thread safety
- **Error Handling**: Use Swift throwing functions with typed LuminaError enum

---

**Estimated Completion**: 54 tasks (50 original + 3 logging + 1 cursor refactor), 43-53 hours of focused implementation work
**Ready for**: Execution with `/implement` or manual task-by-task implementation
