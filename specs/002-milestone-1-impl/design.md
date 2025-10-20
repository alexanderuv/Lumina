# Phase 1: Design Document

**Feature**: Milestone 1 - Linux Support (X11/Wayland) + macOS Wave B
**Date**: 2025-10-20
**Status**: Complete
**Prerequisites**: research.md complete, M0 architecture analyzed

---

## 1. Architecture Overview

Milestone 1 extends Lumina's protocol-based windowing system with Linux platform support while enhancing macOS with Wave B robustness features. The design maintains the three-layer architecture established in M0:

```
┌─────────────────────────────────────────────────────────────┐
│ PUBLIC API LAYER (Platform-Independent)                      │
│ ┌────────────┬────────────┬──────────┬───────────────────┐  │
│ │ LuminaApp  │LuminaWindow│  Event   │  Geometry Types   │  │
│ │ Protocol   │ Protocol   │  System  │  Monitor/Cursor   │  │
│ └────────────┴────────────┴──────────┴───────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ PLATFORM ABSTRACTION LAYER                                   │
│ ┌──────────┬────────────┬────────────┬─────────────────┐   │
│ │  macOS   │  Windows   │  Linux X11 │ Linux Wayland   │   │
│ │ (M0 ✅)  │  (M0 ✅)   │  (M1 🔨)   │   (M1 🔨)       │   │
│ └──────────┴────────────┴────────────┴─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ NATIVE PLATFORM APIs                                         │
│  AppKit  │  Win32    │  XCB       │  wayland-client        │
│  NSApp   │  HWND     │  xcb_*     │  wl_*                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Module Organization

### 2.1 Source Tree Structure

```
Sources/Lumina/
├── Core/                    # Platform-independent (M0 existing + M1 additions)
│   ├── LuminaApp.swift      # [EXTENDED] Add pumpEvents(mode:), WaitUntil
│   ├── LuminaWindow.swift   # [EXTENDED] Add decoration/transparency APIs
│   ├── Events.swift         # [EXTENDED] Add RedrawEvent, MonitorEvent
│   ├── Geometry.swift       # [UNCHANGED] LogicalSize, PhysicalSize, etc.
│   ├── Monitor.swift        # [EXTENDED] Full Monitor struct + enumeration API
│   ├── Cursor.swift         # [UNCHANGED] SystemCursor enum
│   ├── Clipboard.swift      # [NEW] Text clipboard operations
│   ├── Capabilities.swift   # [NEW] Runtime feature detection
│   ├── ControlFlowMode.swift # [NEW] Event loop modes (Wait, Poll, WaitUntil)
│   ├── Errors.swift         # [EXTENDED] Add clipboard/monitor errors
│   ├── WindowID.swift       # [UNCHANGED]
│   └── WindowRegistry.swift # [UNCHANGED]
│
├── Platforms/
│   ├── macOS/               # M0 existing + Wave B enhancements
│   │   ├── MacApplication.swift   # [EXTENDED] pumpEvents(), redraw coalescing
│   │   ├── MacWindow.swift        # [EXTENDED] Decorations, transparency
│   │   ├── MacInput.swift         # [UNCHANGED]
│   │   ├── MacMonitor.swift       # [EXTENDED] Full Monitor API
│   │   ├── MacClipboard.swift     # [NEW] NSPasteboard wrapper
│   │   └── MacCapabilities.swift  # [NEW] macOS feature flags
│   │
│   ├── Windows/             # M0 existing (no changes in M1)
│   │   ├── WinApplication.swift   # [UNCHANGED in M1]
│   │   ├── WinWindow.swift        # [UNCHANGED in M1]
│   │   ├── WinInput.swift         # [UNCHANGED in M1]
│   │   └── WinMonitor.swift       # [UNCHANGED in M1]
│   │
│   └── Linux/               # [NEW] Complete Linux implementation
│       ├── LinuxApplication.swift  # Backend selection (X11/Wayland)
│       ├── X11/
│       │   ├── X11Application.swift   # XCB event loop
│       │   ├── X11Window.swift        # xcb_window_t wrapper
│       │   ├── X11Input.swift         # XCB event translation
│       │   ├── X11Monitor.swift       # XRandR monitor enumeration
│       │   ├── X11Clipboard.swift     # CLIPBOARD selection
│       │   ├── X11Atoms.swift         # Cached atom definitions
│       │   └── X11Capabilities.swift  # X11 feature detection
│       │
│       └── Wayland/
│           ├── WaylandApplication.swift  # wl_display event loop
│           ├── WaylandWindow.swift       # xdg_toplevel wrapper
│           ├── WaylandInput.swift        # wl_pointer/wl_keyboard translation
│           ├── WaylandMonitor.swift      # wl_output enumeration
│           ├── WaylandClipboard.swift    # wl_data_device protocol
│           ├── WaylandProtocols.swift    # Protocol version tracking
│           └── WaylandCapabilities.swift # Compositor capability detection
│
└── CInterop/                # [NEW] C library bindings
    ├── CXCBLinux/
    │   ├── module.modulemap      # XCB, XKB, XInput2, XRandR
    │   └── shims.h               # C helper functions
    └── CWaylandLinux/
        ├── module.modulemap      # wayland-client, libxkbcommon
        └── shims.h               # Wayland helper functions

Tests/LuminaTests/
├── Core/                         # [EXTENDED] Pure logic tests only
│   ├── EventTests.swift          # [EXTENDED] RedrawEvent, MonitorEvent enum tests
│   ├── GeometryTests.swift       # [UNCHANGED] LogicalSize/PhysicalSize conversions
│   ├── ErrorTests.swift          # [EXTENDED] New error enum cases
│   ├── ControlFlowTests.swift    # [NEW] Deadline expiration logic
│   ├── CapabilitiesTests.swift   # [NEW] Capability struct equality/hashing
│   └── MonitorStructTests.swift  # [NEW] Monitor value type tests (no system calls)
│
└── Manual/                       # [NEW] Platform-dependent manual testing
    ├── macOS/
    │   ├── macos-wave-b-checklist.md    # Redraw, decorations, clipboard, monitors
    │   └── macos-wave-a-regression.md   # M0 features still work
    ├── Linux/
    │   ├── linux-x11-checklist.md       # X11 platform validation
    │   ├── linux-wayland-checklist.md   # Wayland platform validation
    │   └── linux-dpi-scenarios.md       # Mixed-DPI testing
    └── Windows/
        └── windows-regression.md        # M0 features still work
```

---

## 3. Type System Design

### 3.1 Core Type Extensions

#### Event System Additions

```swift
// Events.swift - EXTENDED
public enum Event: Sendable {
    case window(WindowEvent)
    case pointer(PointerEvent)
    case keyboard(KeyboardEvent)
    case user(UserEvent)
    case redraw(RedrawEvent)      // [NEW] Wave B
    case monitor(MonitorEvent)    // [NEW] Wave B
}

// [NEW] Redraw events for explicit rendering contract
public enum RedrawEvent: Sendable, Hashable {
    case requested(WindowID, dirtyRect: LogicalRect?)
}

// [NEW] Monitor configuration changes
public enum MonitorEvent: Sendable, Hashable {
    case configurationChanged    // Monitors added/removed/rearranged
}
```

#### Control Flow Mode

```swift
// ControlFlowMode.swift - [NEW]
public enum ControlFlowMode: Sendable {
    case wait                    // Block until event (default, low power)
    case poll                    // Return immediately after available events
    case waitUntil(Deadline)     // Block until event or deadline

    public struct Deadline: Sendable, Hashable {
        let date: Date

        public init(seconds: TimeInterval) {
            self.date = Date(timeIntervalSinceNow: seconds)
        }

        public init(date: Date) {
            self.date = date
        }

        var hasExpired: Bool {
            Date() >= date
        }
    }
}
```

#### Monitor Information

```swift
// Monitor.swift - EXTENDED
public struct MonitorID: Sendable, Hashable {
    let rawValue: Int
}

public struct LogicalRect: Sendable, Hashable {
    public let origin: LogicalPosition
    public let size: LogicalSize

    public init(origin: LogicalPosition, size: LogicalSize) {
        self.origin = origin
        self.size = size
    }
}

public struct Monitor: Sendable, Hashable {
    public let id: MonitorID
    public let name: String
    public let position: LogicalPosition      // Top-left in global space
    public let size: LogicalSize              // Total monitor dimensions
    public let workArea: LogicalRect          // Usable area (excludes panels)
    public let scaleFactor: Float             // DPI multiplier (1.0, 1.5, 2.0, etc.)
    public let isPrimary: Bool                // System primary display

    public init(id: MonitorID, name: String, position: LogicalPosition,
                size: LogicalSize, workArea: LogicalRect,
                scaleFactor: Float, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.position = position
        self.size = size
        self.workArea = workArea
        self.scaleFactor = scaleFactor
        self.isPrimary = isPrimary
    }
}
```

#### Clipboard Operations

```swift
// Clipboard.swift - [NEW]
@MainActor
public struct Clipboard: Sendable {
    private init() {}  // No instances, static API only

    /// Read UTF-8 text from system clipboard
    /// - Returns: Text string if available, nil if clipboard empty
    /// - Throws: LuminaError.clipboardAccessDenied or .clipboardReadFailed
    public static func readText() throws -> String?

    /// Write UTF-8 text to system clipboard
    /// - Parameter text: Text to write
    /// - Throws: LuminaError.clipboardAccessDenied or .clipboardWriteFailed
    public static func writeText(_ text: String) throws

    /// Check if clipboard contents changed since last read/write
    /// - Returns: true if external modification detected
    public static func hasChanged() -> Bool
}
```

#### Capability System

```swift
// Capabilities.swift - [NEW]
public struct WindowCapabilities: Sendable, Hashable {
    public let supportsTransparency: Bool
    public let supportsAlwaysOnTop: Bool
    public let supportsDecorationToggle: Bool
    public let supportsClientSideDecorations: Bool  // Wayland-specific

    public init(supportsTransparency: Bool = false,
                supportsAlwaysOnTop: Bool = false,
                supportsDecorationToggle: Bool = false,
                supportsClientSideDecorations: Bool = false) {
        self.supportsTransparency = supportsTransparency
        self.supportsAlwaysOnTop = supportsAlwaysOnTop
        self.supportsDecorationToggle = supportsDecorationToggle
        self.supportsClientSideDecorations = supportsClientSideDecorations
    }
}

public struct ClipboardCapabilities: Sendable, Hashable {
    public let supportsText: Bool
    public let supportsImages: Bool   // Future
    public let supportsHTML: Bool     // Future

    public init(supportsText: Bool = false,
                supportsImages: Bool = false,
                supportsHTML: Bool = false) {
        self.supportsText = supportsText
        self.supportsImages = supportsImages
        self.supportsHTML = supportsHTML
    }
}

public struct MonitorCapabilities: Sendable, Hashable {
    public let supportsDynamicRefreshRate: Bool  // ProMotion (macOS)
    public let supportsFractionalScaling: Bool

    public init(supportsDynamicRefreshRate: Bool = false,
                supportsFractionalScaling: Bool = false) {
        self.supportsDynamicRefreshRate = supportsDynamicRefreshRate
        self.supportsFractionalScaling = supportsFractionalScaling
    }
}
```

---

### 3.2 Protocol Extensions

#### LuminaApp Protocol Changes

```swift
// LuminaApp.swift - EXTENDED
@MainActor
public protocol LuminaApp: Sendable {
    // ===== M0 Existing =====
    init() throws
    mutating func run() throws                    // Blocking loop until quit
    mutating func poll() -> Event?                // Non-blocking single event
    mutating func wait()                          // Block until event available
    nonisolated func postUserEvent(_ event: UserEvent)
    mutating func quit()
    mutating func createWindow(title: String,
                               size: LogicalSize,
                               resizable: Bool) throws -> any LuminaWindow
    var exitOnLastWindowClosed: Bool { get set }

    // ===== M1 Additions =====
    /// Unified event pump with control flow modes
    /// - Parameter mode: Control flow strategy (wait, poll, waitUntil)
    /// - Returns: Next event if available, nil otherwise
    mutating func pumpEvents(mode: ControlFlowMode) -> Event?

    /// Query monitor capabilities for this platform
    static func monitorCapabilities() -> MonitorCapabilities

    /// Query clipboard capabilities for this platform
    static func clipboardCapabilities() -> ClipboardCapabilities
}

// Default implementations for backward compatibility
extension LuminaApp {
    public mutating func run() throws {
        while true {
            if let event = pumpEvents(mode: .wait) {
                if case .window(.closed(_)) = event {
                    if exitOnLastWindowClosed {
                        quit()
                        break
                    }
                }
            }
        }
    }

    public mutating func poll() -> Event? {
        pumpEvents(mode: .poll)
    }

    public mutating func wait() {
        _ = pumpEvents(mode: .wait)
    }
}
```

#### LuminaWindow Protocol Changes

```swift
// LuminaWindow.swift - EXTENDED
@MainActor
public protocol LuminaWindow: Sendable {
    // ===== M0 Existing =====
    var id: WindowID { get }
    func show()
    func hide()
    consuming func close()
    func setTitle(_ title: String)
    func size() -> LogicalSize
    func resize(_ size: LogicalSize)
    func position() -> LogicalPosition
    func moveTo(_ position: LogicalPosition)
    func setMinSize(_ size: LogicalSize)
    func setMaxSize(_ size: LogicalSize)
    func requestFocus()
    func scaleFactor() -> Float

    // ===== M1 Additions (Wave B) =====
    /// Request a redraw of window contents
    /// Triggers RedrawEvent.requested in event queue
    func requestRedraw()

    /// Toggle window decorations (title bar, borders)
    /// - Parameter decorated: true for standard decorations, false for borderless
    /// - Throws: LuminaError.unsupportedPlatformFeature if not supported
    func setDecorated(_ decorated: Bool) throws

    /// Set always-on-top (floating) window behavior
    /// - Parameter alwaysOnTop: true to float above other windows
    /// - Throws: LuminaError.unsupportedPlatformFeature if not supported
    func setAlwaysOnTop(_ alwaysOnTop: Bool) throws

    /// Enable window transparency (alpha channel background)
    /// - Parameter transparent: true for transparent background
    /// - Throws: LuminaError.unsupportedPlatformFeature if not supported
    func setTransparent(_ transparent: Bool) throws

    /// Query window-specific capabilities
    func capabilities() -> WindowCapabilities

    /// Get monitor this window currently resides on
    func currentMonitor() throws -> Monitor
}

// Default implementations for platforms without Wave B support
extension LuminaWindow {
    public func requestRedraw() {
        // No-op on platforms without redraw events (legacy)
    }

    public func setDecorated(_ decorated: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(feature: "window decorations")
    }

    public func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(feature: "always-on-top")
    }

    public func setTransparent(_ transparent: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(feature: "transparency")
    }

    public func capabilities() -> WindowCapabilities {
        WindowCapabilities()  // All false
    }
}
```

#### Global Monitor Enumeration

```swift
// Monitor.swift - EXTENDED
/// Enumerate all connected monitors
/// - Returns: Array of monitors in system order (primary first)
/// - Throws: LuminaError.monitorEnumerationFailed
@MainActor
public func enumerateMonitors() throws -> [Monitor]

/// Get primary monitor
/// - Returns: Primary monitor info
/// - Throws: LuminaError.monitorEnumerationFailed
@MainActor
public func primaryMonitor() throws -> Monitor {
    let monitors = try enumerateMonitors()
    guard let primary = monitors.first(where: { $0.isPrimary }) else {
        throw LuminaError.monitorEnumerationFailed("No primary monitor found")
    }
    return primary
}
```

---

### 3.3 Error Handling Extensions

```swift
// Errors.swift - EXTENDED
public enum LuminaError: Error, Sendable {
    // ===== M0 Existing =====
    case platformInitializationFailed(String)
    case windowCreationFailed(String)
    case invalidWindowID(WindowID)

    // ===== M1 Additions =====
    case clipboardAccessDenied
    case clipboardReadFailed(String)
    case clipboardWriteFailed(String)
    case monitorEnumerationFailed(String)
    case unsupportedPlatformFeature(feature: String)
    case waylandProtocolMissing(protocol: String)
    case x11ExtensionMissing(extension: String)
}

extension LuminaError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .platformInitializationFailed(let reason):
            return "Platform initialization failed: \(reason)"
        case .windowCreationFailed(let reason):
            return "Window creation failed: \(reason)"
        case .invalidWindowID(let id):
            return "Invalid window ID: \(id)"
        case .clipboardAccessDenied:
            return "Clipboard access denied by system"
        case .clipboardReadFailed(let reason):
            return "Clipboard read failed: \(reason)"
        case .clipboardWriteFailed(let reason):
            return "Clipboard write failed: \(reason)"
        case .monitorEnumerationFailed(let reason):
            return "Monitor enumeration failed: \(reason)"
        case .unsupportedPlatformFeature(let feature):
            return "Feature not supported on this platform: \(feature)"
        case .waylandProtocolMissing(let proto):
            return "Required Wayland protocol missing: \(proto)"
        case .x11ExtensionMissing(let ext):
            return "Required X11 extension missing: \(ext)"
        }
    }
}
```

---

## 4. Platform-Specific Implementations

### 4.1 macOS Wave B Implementation

#### MacApplication Changes

```swift
// Platforms/macOS/MacApplication.swift - EXTENDED
@MainActor
struct MacApplication: LuminaApp {
    // ===== M0 Existing State =====
    private var shouldQuit: Bool = false
    private let userEventQueue = UserEventQueue()
    private let windowEventQueue = WindowEventQueue()
    private var windowRegistry = WindowRegistry<Int>()  // NSWindow.windowNumber -> WindowID
    var exitOnLastWindowClosed: Bool = false

    // ===== M1 Additions =====
    private var redrawRequests: Set<WindowID> = []           // Windows needing redraw
    private var displayLink: CADisplayLink?                  // Frame pacing
    private var lastChangeCount: Int = NSPasteboard.general.changeCount  // Clipboard tracking

    // ===== M1 Enhanced Event Pump =====
    mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
        // 1. Process redraw requests first (priority)
        if let windowID = redrawRequests.first {
            redrawRequests.remove(windowID)
            return .redraw(.requested(windowID, dirtyRect: nil))
        }

        // 2. Process user events
        if let userEvent = userEventQueue.dequeue() {
            return .user(userEvent)
        }

        // 3. Process window close events
        if let windowID = windowEventQueue.dequeue() {
            return .window(.closed(windowID))
        }

        // 4. Determine NSRunLoop timeout based on mode
        let timeout: Date = switch mode {
        case .wait:
            .distantFuture
        case .poll:
            .distantPast
        case .waitUntil(let deadline):
            deadline.date
        }

        // 5. Pump NSApp event loop
        while let nsEvent = NSApp.nextEvent(matching: .any, until: timeout,
                                            inMode: .default, dequeue: true) {
            NSApp.sendEvent(nsEvent)

            // Translate NSEvent to Lumina event
            if let event = translateNSEvent(nsEvent) {
                return event
            }

            // Exit poll mode after single iteration
            if case .poll = mode { break }
        }

        // 6. Check queues again after NSApp processing
        if let userEvent = userEventQueue.dequeue() {
            return .user(userEvent)
        }
        if let windowID = windowEventQueue.dequeue() {
            return .window(.closed(windowID))
        }

        return nil
    }

    // ===== Capability Queries =====
    static func monitorCapabilities() -> MonitorCapabilities {
        MonitorCapabilities(
            supportsDynamicRefreshRate: true,  // ProMotion displays
            supportsFractionalScaling: false   // macOS uses integer scaling
        )
    }

    static func clipboardCapabilities() -> ClipboardCapabilities {
        ClipboardCapabilities(supportsText: true)
    }
}

// Helper for redraw tracking
extension MacApplication {
    mutating func markWindowNeedsRedraw(_ windowID: WindowID) {
        redrawRequests.insert(windowID)
    }
}
```

#### MacWindow Changes

```swift
// Platforms/macOS/MacWindow.swift - EXTENDED
@MainActor
struct MacWindow: LuminaWindow {
    let id: WindowID
    let nsWindow: NSWindow
    weak var application: MacApplication?

    // ===== M0 Existing Methods (unchanged) =====
    func show() { nsWindow.makeKeyAndOrderFront(nil) }
    func hide() { nsWindow.orderOut(nil) }
    // ... (rest of M0 methods)

    // ===== M1 Wave B Additions =====
    func requestRedraw() {
        nsWindow.contentView?.setNeedsDisplay(nsWindow.contentView!.bounds)
        application?.markWindowNeedsRedraw(id)
    }

    func setDecorated(_ decorated: Bool) throws {
        if decorated {
            nsWindow.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        } else {
            nsWindow.styleMask = .borderless
        }
        nsWindow.invalidateShadow()
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        nsWindow.level = alwaysOnTop ? .floating : .normal
    }

    func setTransparent(_ transparent: Bool) throws {
        nsWindow.isOpaque = !transparent
        nsWindow.backgroundColor = transparent ? .clear : .windowBackgroundColor
        nsWindow.hasShadow = !transparent
    }

    func capabilities() -> WindowCapabilities {
        WindowCapabilities(
            supportsTransparency: true,
            supportsAlwaysOnTop: true,
            supportsDecorationToggle: true,
            supportsClientSideDecorations: false  // AppKit uses SSD
        )
    }

    func currentMonitor() throws -> Monitor {
        guard let screen = nsWindow.screen else {
            throw LuminaError.monitorEnumerationFailed("Window has no associated screen")
        }
        return try MacMonitor.fromNSScreen(screen)
    }
}
```

#### MacMonitor Implementation

```swift
// Platforms/macOS/MacMonitor.swift - EXTENDED
@MainActor
struct MacMonitor {
    static func fromNSScreen(_ screen: NSScreen) throws -> Monitor {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int else {
            throw LuminaError.monitorEnumerationFailed("Cannot get screen number")
        }

        let frame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Convert from AppKit's bottom-left origin to top-left
        let globalHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? frame.maxY
        let topLeftY = globalHeight - frame.maxY

        return Monitor(
            id: MonitorID(rawValue: screenNumber),
            name: screen.localizedName,
            position: LogicalPosition(
                x: Float(frame.origin.x),
                y: Float(topLeftY)
            ),
            size: LogicalSize(
                width: Float(frame.width),
                height: Float(frame.height)
            ),
            workArea: LogicalRect(
                origin: LogicalPosition(
                    x: Float(visibleFrame.origin.x),
                    y: Float(globalHeight - visibleFrame.maxY)
                ),
                size: LogicalSize(
                    width: Float(visibleFrame.width),
                    height: Float(visibleFrame.height)
                )
            ),
            scaleFactor: Float(screen.backingScaleFactor),
            isPrimary: screen == NSScreen.main
        )
    }
}

public func enumerateMonitors() throws -> [Monitor] {
    try NSScreen.screens.map { try MacMonitor.fromNSScreen($0) }
}
```

#### MacClipboard Implementation

```swift
// Platforms/macOS/MacClipboard.swift - [NEW]
@MainActor
struct MacClipboard {
    private static var lastChangeCount: Int = NSPasteboard.general.changeCount

    static func readText() throws -> String? {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        return pasteboard.string(forType: .string)
    }

    static func writeText(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw LuminaError.clipboardWriteFailed("NSPasteboard.setString failed")
        }
        lastChangeCount = pasteboard.changeCount
    }

    static func hasChanged() -> Bool {
        let currentCount = NSPasteboard.general.changeCount
        return currentCount != lastChangeCount
    }
}

// Wire to global Clipboard API
extension Clipboard {
    #if os(macOS)
    public static func readText() throws -> String? {
        try MacClipboard.readText()
    }

    public static func writeText(_ text: String) throws {
        try MacClipboard.writeText(text)
    }

    public static func hasChanged() -> Bool {
        MacClipboard.hasChanged()
    }
    #endif
}
```

---

### 4.2 Linux X11 Implementation

#### X11Application Structure

```swift
// Platforms/Linux/X11/X11Application.swift - [NEW]
#if os(Linux)
import CXCBLinux

@MainActor
struct X11Application: LuminaApp {
    private let connection: OpaquePointer     // xcb_connection_t*
    private let screen: OpaquePointer         // xcb_screen_t*
    private let atoms: X11Atoms               // Cached atom IDs
    private let xkbContext: OpaquePointer     // xkb_context*
    private let xkbKeymap: OpaquePointer?     // xkb_keymap*
    private let xkbState: OpaquePointer?      // xkb_state*

    private var shouldQuit: Bool = false
    private var eventQueue: [Event] = []
    private var userEventQueue = UserEventQueue()
    private var windowRegistry = WindowRegistry<UInt32>()  // xcb_window_t -> WindowID
    var exitOnLastWindowClosed: Bool = false

    init() throws {
        // 1. Connect to X server
        var screenNum: Int32 = 0
        guard let conn = xcb_connect(nil, &screenNum) else {
            throw LuminaError.platformInitializationFailed("XCB connection failed")
        }
        guard xcb_connection_has_error(conn) == 0 else {
            xcb_disconnect(conn)
            throw LuminaError.platformInitializationFailed("XCB connection error")
        }
        self.connection = conn

        // 2. Get screen
        let setup = xcb_get_setup(conn)
        var iter = xcb_setup_roots_iterator(setup)
        for _ in 0..<screenNum {
            xcb_screen_next(&iter)
        }
        self.screen = iter.data

        // 3. Initialize XKB for keyboard handling
        guard let ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS) else {
            throw LuminaError.platformInitializationFailed("xkb_context creation failed")
        }
        self.xkbContext = ctx

        // TODO: Query XKB keymap from server
        self.xkbKeymap = nil
        self.xkbState = nil

        // 4. Cache essential atoms
        self.atoms = try X11Atoms.cache(connection: conn)

        // 5. Initialize XInput2 for high-precision input
        // TODO: XInput2 setup
    }

    mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
        // 1. Process user events first
        if let userEvent = userEventQueue.dequeue() {
            return .user(userEvent)
        }

        // 2. Process queued Lumina events
        if !eventQueue.isEmpty {
            return eventQueue.removeFirst()
        }

        // 3. Poll X11 events based on control flow mode
        switch mode {
        case .wait:
            // Blocking wait for event
            if let xcbEvent = xcb_wait_for_event(connection) {
                translateAndEnqueueXCBEvent(xcbEvent)
                xcbEvent.deallocate()
            }

        case .poll:
            // Non-blocking poll all available
            while let xcbEvent = xcb_poll_for_event(connection) {
                translateAndEnqueueXCBEvent(xcbEvent)
                xcbEvent.deallocate()
            }

        case .waitUntil(let deadline):
            // Poll with timeout using select() on XCB file descriptor
            let fd = xcb_get_file_descriptor(connection)
            var readSet = fd_set()
            // TODO: fd_set manipulation (Swift doesn't expose FD_SET directly)
            let timeoutSec = max(0, deadline.date.timeIntervalSinceNow)
            var timeout = timeval(tv_sec: Int(timeoutSec), tv_usec: 0)
            select(fd + 1, &readSet, nil, nil, &timeout)

            while let xcbEvent = xcb_poll_for_event(connection) {
                translateAndEnqueueXCBEvent(xcbEvent)
                xcbEvent.deallocate()
            }
        }

        // 4. Return next event if available
        return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
    }

    private mutating func translateAndEnqueueXCBEvent(_ xcbEvent: OpaquePointer) {
        let responseType = xcbEvent.load(as: UInt8.self) & 0x7F

        switch responseType {
        case UInt8(XCB_EXPOSE):
            // Redraw event
            let exposeEvent = xcbEvent.load(as: xcb_expose_event_t.self)
            if let windowID = windowRegistry.lookup(nativeHandle: exposeEvent.window) {
                eventQueue.append(.redraw(.requested(windowID, dirtyRect: nil)))
            }

        case UInt8(XCB_CONFIGURE_NOTIFY):
            // Resize/move event
            let configEvent = xcbEvent.load(as: xcb_configure_notify_event_t.self)
            if let windowID = windowRegistry.lookup(nativeHandle: configEvent.window) {
                let size = LogicalSize(width: Float(configEvent.width), height: Float(configEvent.height))
                let position = LogicalPosition(x: Float(configEvent.x), y: Float(configEvent.y))
                eventQueue.append(.window(.resized(windowID, size)))
                eventQueue.append(.window(.moved(windowID, position)))
            }

        case UInt8(XCB_BUTTON_PRESS), UInt8(XCB_BUTTON_RELEASE):
            // Mouse button events
            let buttonEvent = xcbEvent.load(as: xcb_button_press_event_t.self)
            if let event = X11Input.translateButtonEvent(buttonEvent, registry: windowRegistry) {
                eventQueue.append(event)
            }

        case UInt8(XCB_MOTION_NOTIFY):
            // Mouse move
            let motionEvent = xcbEvent.load(as: xcb_motion_notify_event_t.self)
            if let event = X11Input.translateMotionEvent(motionEvent, registry: windowRegistry) {
                eventQueue.append(event)
            }

        case UInt8(XCB_KEY_PRESS), UInt8(XCB_KEY_RELEASE):
            // Keyboard events
            let keyEvent = xcbEvent.load(as: xcb_key_press_event_t.self)
            if let event = X11Input.translateKeyEvent(keyEvent, xkbState: xkbState, registry: windowRegistry) {
                eventQueue.append(event)
            }

        case UInt8(XCB_CLIENT_MESSAGE):
            // Window close, protocol events
            let clientEvent = xcbEvent.load(as: xcb_client_message_event_t.self)
            if clientEvent.type == atoms.WM_PROTOCOLS {
                let protocol = clientEvent.data.data32.0
                if protocol == atoms.WM_DELETE_WINDOW {
                    if let windowID = windowRegistry.lookup(nativeHandle: clientEvent.window) {
                        eventQueue.append(.window(.closed(windowID)))
                    }
                }
            }

        default:
            break  // Ignore unknown events
        }
    }

    nonisolated func postUserEvent(_ event: UserEvent) {
        // Thread-safe user event posting
        Task { @MainActor in
            userEventQueue.enqueue(event)
            // TODO: Wake event loop by sending dummy X11 event
        }
    }

    mutating func quit() {
        shouldQuit = true
    }

    mutating func createWindow(title: String, size: LogicalSize, resizable: Bool) throws -> any LuminaWindow {
        try X11Window.create(
            connection: connection,
            screen: screen,
            atoms: atoms,
            title: title,
            size: size,
            resizable: resizable,
            registry: &windowRegistry
        )
    }

    static func monitorCapabilities() -> MonitorCapabilities {
        MonitorCapabilities(
            supportsDynamicRefreshRate: false,
            supportsFractionalScaling: true  // Via Xft.dpi
        )
    }

    static func clipboardCapabilities() -> ClipboardCapabilities {
        ClipboardCapabilities(supportsText: true)
    }
}
#endif
```

#### X11Atoms (Cached Atom IDs)

```swift
// Platforms/Linux/X11/X11Atoms.swift - [NEW]
#if os(Linux)
import CXCBLinux

struct X11Atoms {
    let WM_PROTOCOLS: UInt32
    let WM_DELETE_WINDOW: UInt32
    let _NET_WM_NAME: UInt32
    let _NET_WM_STATE: UInt32
    let _NET_WM_STATE_ABOVE: UInt32
    let _NET_WM_STATE_FULLSCREEN: UInt32
    let _MOTIF_WM_HINTS: UInt32
    let CLIPBOARD: UInt32
    let UTF8_STRING: UInt32

    static func cache(connection: OpaquePointer) throws -> X11Atoms {
        func intern(_ name: String) throws -> UInt32 {
            let cookie = xcb_intern_atom(connection, 0, UInt16(name.utf8.count), name)
            guard let reply = xcb_intern_atom_reply(connection, cookie, nil) else {
                throw LuminaError.x11ExtensionMissing(extension: name)
            }
            defer { reply.deallocate() }
            return reply.pointee.atom
        }

        return X11Atoms(
            WM_PROTOCOLS: try intern("WM_PROTOCOLS"),
            WM_DELETE_WINDOW: try intern("WM_DELETE_WINDOW"),
            _NET_WM_NAME: try intern("_NET_WM_NAME"),
            _NET_WM_STATE: try intern("_NET_WM_STATE"),
            _NET_WM_STATE_ABOVE: try intern("_NET_WM_STATE_ABOVE"),
            _NET_WM_STATE_FULLSCREEN: try intern("_NET_WM_STATE_FULLSCREEN"),
            _MOTIF_WM_HINTS: try intern("_MOTIF_WM_HINTS"),
            CLIPBOARD: try intern("CLIPBOARD"),
            UTF8_STRING: try intern("UTF8_STRING")
        )
    }
}
#endif
```

#### X11Window Implementation

```swift
// Platforms/Linux/X11/X11Window.swift - [NEW]
#if os(Linux)
import CXCBLinux

@MainActor
struct X11Window: LuminaWindow {
    let id: WindowID
    let xcbWindow: UInt32  // xcb_window_t
    let connection: OpaquePointer
    let atoms: X11Atoms

    static func create(
        connection: OpaquePointer,
        screen: OpaquePointer,
        atoms: X11Atoms,
        title: String,
        size: LogicalSize,
        resizable: Bool,
        registry: inout WindowRegistry<UInt32>
    ) throws -> X11Window {
        let screenData = screen.load(as: xcb_screen_t.self)
        let windowID = xcb_generate_id(connection)

        // Create window
        let valueMask: UInt32 = UInt32(XCB_CW_BACK_PIXEL | XCB_CW_EVENT_MASK)
        var valueList: [UInt32] = [
            screenData.white_pixel,  // Background color
            UInt32(XCB_EVENT_MASK_EXPOSURE |
                   XCB_EVENT_MASK_STRUCTURE_NOTIFY |
                   XCB_EVENT_MASK_BUTTON_PRESS |
                   XCB_EVENT_MASK_BUTTON_RELEASE |
                   XCB_EVENT_MASK_POINTER_MOTION |
                   XCB_EVENT_MASK_KEY_PRESS |
                   XCB_EVENT_MASK_KEY_RELEASE |
                   XCB_EVENT_MASK_FOCUS_CHANGE)
        ]

        xcb_create_window(
            connection,
            XCB_COPY_FROM_PARENT,
            windowID,
            screenData.root,
            0, 0,  // x, y
            UInt16(size.width), UInt16(size.height),
            0,  // border width
            UInt16(XCB_WINDOW_CLASS_INPUT_OUTPUT),
            screenData.root_visual,
            valueMask,
            &valueList
        )

        // Set WM_PROTOCOLS for close button
        var protocols = [atoms.WM_DELETE_WINDOW]
        xcb_change_property(connection, UInt8(XCB_PROP_MODE_REPLACE),
                           windowID, atoms.WM_PROTOCOLS, XCB_ATOM_ATOM, 32, 1, &protocols)

        // Set title
        xcb_change_property(connection, UInt8(XCB_PROP_MODE_REPLACE),
                           windowID, atoms._NET_WM_NAME, atoms.UTF8_STRING, 8,
                           UInt32(title.utf8.count), title)

        xcb_flush(connection)

        let windowID_lumina = registry.register(nativeHandle: windowID)

        return X11Window(
            id: windowID_lumina,
            xcbWindow: windowID,
            connection: connection,
            atoms: atoms
        )
    }

    func show() {
        xcb_map_window(connection, xcbWindow)
        xcb_flush(connection)
    }

    func hide() {
        xcb_unmap_window(connection, xcbWindow)
        xcb_flush(connection)
    }

    consuming func close() {
        xcb_destroy_window(connection, xcbWindow)
        xcb_flush(connection)
    }

    func setTitle(_ title: String) {
        xcb_change_property(connection, UInt8(XCB_PROP_MODE_REPLACE),
                           xcbWindow, atoms._NET_WM_NAME, atoms.UTF8_STRING, 8,
                           UInt32(title.utf8.count), title)
        xcb_flush(connection)
    }

    func requestRedraw() {
        // Force expose event
        xcb_clear_area(connection, 1, xcbWindow, 0, 0, 0, 0)
        xcb_flush(connection)
    }

    func setDecorated(_ decorated: Bool) throws {
        // Use _MOTIF_WM_HINTS to toggle decorations
        struct MotifWmHints {
            var flags: UInt32 = 2  // MWM_HINTS_DECORATIONS
            var functions: UInt32 = 0
            var decorations: UInt32
            var input_mode: Int32 = 0
            var status: UInt32 = 0
        }

        var hints = MotifWmHints(decorations: decorated ? 1 : 0)
        xcb_change_property(connection, UInt8(XCB_PROP_MODE_REPLACE),
                           xcbWindow, atoms._MOTIF_WM_HINTS, atoms._MOTIF_WM_HINTS,
                           32, 5, &hints)
        xcb_flush(connection)
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        if alwaysOnTop {
            var state = [atoms._NET_WM_STATE_ABOVE]
            xcb_change_property(connection, UInt8(XCB_PROP_MODE_APPEND),
                               xcbWindow, atoms._NET_WM_STATE, XCB_ATOM_ATOM, 32, 1, &state)
        } else {
            // TODO: Remove property value
        }
        xcb_flush(connection)
    }

    func setTransparent(_ transparent: Bool) throws {
        // X11 transparency requires ARGB visual (complex setup)
        // For M1, throw unsupported
        throw LuminaError.unsupportedPlatformFeature(feature: "transparency on X11")
    }

    func capabilities() -> WindowCapabilities {
        WindowCapabilities(
            supportsTransparency: false,  // Requires ARGB visual setup
            supportsAlwaysOnTop: true,
            supportsDecorationToggle: true,
            supportsClientSideDecorations: false
        )
    }

    // ... (rest of LuminaWindow methods)
}
#endif
```

---

### 4.3 Linux Wayland Implementation

#### WaylandApplication Structure

```swift
// Platforms/Linux/Wayland/WaylandApplication.swift - [NEW]
#if os(Linux)
import CWaylandLinux

@MainActor
struct WaylandApplication: LuminaApp {
    private let display: OpaquePointer        // wl_display*
    private let registry: OpaquePointer       // wl_registry*
    private let compositor: OpaquePointer     // wl_compositor*
    private let wmBase: OpaquePointer         // xdg_wm_base*
    private let seat: OpaquePointer?          // wl_seat*
    private let protocols: WaylandProtocols   // Available protocol versions

    private var shouldQuit: Bool = false
    private var eventQueue: [Event] = []
    private var userEventQueue = UserEventQueue()
    private var windowRegistry = WindowRegistry<UInt32>()  // wl_surface ID -> WindowID
    var exitOnLastWindowClosed: Bool = false

    init() throws {
        // 1. Connect to Wayland display
        guard let disp = wl_display_connect(nil) else {
            throw LuminaError.platformInitializationFailed("Wayland connection failed (no WAYLAND_DISPLAY)")
        }
        self.display = disp

        // 2. Get registry and bind essential protocols
        guard let reg = wl_display_get_registry(disp) else {
            throw LuminaError.platformInitializationFailed("wl_display_get_registry failed")
        }
        self.registry = reg

        // 3. Enumerate globals and bind protocols
        var compositor: OpaquePointer? = nil
        var wmBase: OpaquePointer? = nil
        var seat: OpaquePointer? = nil
        var protocols = WaylandProtocols()

        // Set up registry listener
        // TODO: Implement wl_registry listener callbacks
        // - Bind wl_compositor (REQUIRED)
        // - Bind xdg_wm_base (REQUIRED)
        // - Bind wl_seat (REQUIRED)
        // - Check for optional protocols (fractional_scale, decorations, etc.)

        // Roundtrip to process globals
        wl_display_roundtrip(disp)

        guard let comp = compositor else {
            throw LuminaError.waylandProtocolMissing(protocol: "wl_compositor")
        }
        guard let base = wmBase else {
            throw LuminaError.waylandProtocolMissing(protocol: "xdg_wm_base")
        }

        self.compositor = comp
        self.wmBase = base
        self.seat = seat
        self.protocols = protocols
    }

    mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
        // 1. Process user events first
        if let userEvent = userEventQueue.dequeue() {
            return .user(userEvent)
        }

        // 2. Process queued Lumina events
        if !eventQueue.isEmpty {
            return eventQueue.removeFirst()
        }

        // 3. Dispatch Wayland events based on control flow mode
        switch mode {
        case .wait:
            // Blocking wait
            wl_display_dispatch(display)

        case .poll:
            // Non-blocking dispatch pending
            wl_display_dispatch_pending(display)

        case .waitUntil(let deadline):
            // Poll with timeout using select() on Wayland fd
            let fd = wl_display_get_fd(display)
            var readSet = fd_set()
            // TODO: fd_set manipulation
            let timeoutSec = max(0, deadline.date.timeIntervalSinceNow)
            var timeout = timeval(tv_sec: Int(timeoutSec), tv_usec: 0)
            select(fd + 1, &readSet, nil, nil, &timeout)

            wl_display_dispatch_pending(display)
        }

        // 4. Return next event if available
        return eventQueue.isEmpty ? nil : eventQueue.removeFirst()
    }

    nonisolated func postUserEvent(_ event: UserEvent) {
        // Thread-safe user event posting
        Task { @MainActor in
            userEventQueue.enqueue(event)
            // TODO: Wake event loop
        }
    }

    mutating func quit() {
        shouldQuit = true
    }

    mutating func createWindow(title: String, size: LogicalSize, resizable: Bool) throws -> any LuminaWindow {
        try WaylandWindow.create(
            display: display,
            compositor: compositor,
            wmBase: wmBase,
            title: title,
            size: size,
            resizable: resizable,
            registry: &windowRegistry
        )
    }

    static func monitorCapabilities() -> MonitorCapabilities {
        MonitorCapabilities(
            supportsDynamicRefreshRate: false,
            supportsFractionalScaling: true  // Via wp_fractional_scale_v1
        )
    }

    static func clipboardCapabilities() -> ClipboardCapabilities {
        ClipboardCapabilities(supportsText: true)
    }
}

struct WaylandProtocols {
    var hasFractionalScale: Bool = false
    var hasXdgDecoration: Bool = false
    var fractionalScaleVersion: UInt32 = 0
    var xdgDecorationVersion: UInt32 = 0
}
#endif
```

#### WaylandWindow Implementation

```swift
// Platforms/Linux/Wayland/WaylandWindow.swift - [NEW]
#if os(Linux)
import CWaylandLinux

@MainActor
struct WaylandWindow: LuminaWindow {
    let id: WindowID
    let surface: OpaquePointer       // wl_surface*
    let xdgSurface: OpaquePointer    // xdg_surface*
    let xdgToplevel: OpaquePointer   // xdg_toplevel*
    let display: OpaquePointer       // wl_display*

    static func create(
        display: OpaquePointer,
        compositor: OpaquePointer,
        wmBase: OpaquePointer,
        title: String,
        size: LogicalSize,
        resizable: Bool,
        registry: inout WindowRegistry<UInt32>
    ) throws -> WaylandWindow {
        // 1. Create wl_surface
        guard let surface = wl_compositor_create_surface(compositor) else {
            throw LuminaError.windowCreationFailed("wl_compositor_create_surface failed")
        }

        // 2. Get xdg_surface role
        guard let xdgSurface = xdg_wm_base_get_xdg_surface(wmBase, surface) else {
            throw LuminaError.windowCreationFailed("xdg_wm_base_get_xdg_surface failed")
        }

        // 3. Get xdg_toplevel (desktop window)
        guard let toplevel = xdg_surface_get_toplevel(xdgSurface) else {
            throw LuminaError.windowCreationFailed("xdg_surface_get_toplevel failed")
        }

        // 4. Configure toplevel
        xdg_toplevel_set_title(toplevel, title)
        xdg_toplevel_set_min_size(toplevel, 1, 1)
        if !resizable {
            xdg_toplevel_set_max_size(toplevel, Int32(size.width), Int32(size.height))
        }

        // 5. Commit surface
        wl_surface_commit(surface)

        // Roundtrip to process configure event
        wl_display_roundtrip(display)

        let surfaceID = UInt32(bitPattern: surface)  // Use pointer as ID
        let windowID = registry.register(nativeHandle: surfaceID)

        return WaylandWindow(
            id: windowID,
            surface: surface,
            xdgSurface: xdgSurface,
            xdgToplevel: toplevel,
            display: display
        )
    }

    func show() {
        // Wayland windows are visible once surface is committed
        // No explicit show/hide API
    }

    func hide() {
        // TODO: Unmap surface (compositor-dependent)
    }

    consuming func close() {
        xdg_toplevel_destroy(xdgToplevel)
        xdg_surface_destroy(xdgSurface)
        wl_surface_destroy(surface)
    }

    func setTitle(_ title: String) {
        xdg_toplevel_set_title(xdgToplevel, title)
        wl_surface_commit(surface)
    }

    func requestRedraw() {
        wl_surface_damage(surface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(surface)
    }

    func setDecorated(_ decorated: Bool) throws {
        // Requires xdg-decoration protocol
        throw LuminaError.unsupportedPlatformFeature(feature: "decoration toggle on Wayland (protocol unavailable)")
    }

    func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        // Compositor-dependent, no standard protocol
        throw LuminaError.unsupportedPlatformFeature(feature: "always-on-top on Wayland")
    }

    func setTransparent(_ transparent: Bool) throws {
        // Wayland supports per-pixel alpha natively
        // TODO: Set surface format to ARGB8888
    }

    func capabilities() -> WindowCapabilities {
        WindowCapabilities(
            supportsTransparency: true,  // Native in Wayland
            supportsAlwaysOnTop: false,  // No standard protocol
            supportsDecorationToggle: false,  // M1 limitation
            supportsClientSideDecorations: true
        )
    }

    // ... (rest of LuminaWindow methods)
}
#endif
```

---

### 4.4 Linux Backend Selection

```swift
// Platforms/Linux/LinuxApplication.swift - [NEW]
#if os(Linux)

/// Create Lumina application with automatic backend selection
/// Prefers Wayland if WAYLAND_DISPLAY is set, falls back to X11
public func createLuminaApp() throws -> some LuminaApp {
    if let waylandDisplay = ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"],
       !waylandDisplay.isEmpty {
        do {
            return try WaylandApplication()
        } catch {
            // Fall back to X11 if Wayland init fails
            print("Wayland init failed, falling back to X11: \(error)")
        }
    }

    if ProcessInfo.processInfo.environment["DISPLAY"] != nil {
        return try X11Application()
    }

    throw LuminaError.platformInitializationFailed("No display server detected (no WAYLAND_DISPLAY or DISPLAY)")
}

#endif
```

---

## 5. Thread Safety & Concurrency Design

### 5.1 @MainActor Enforcement

All windowing APIs continue M0 pattern of `@MainActor` isolation:

```swift
@MainActor
public protocol LuminaApp: Sendable { /* ... */ }

@MainActor
public protocol LuminaWindow: Sendable { /* ... */ }

@MainActor
public struct Clipboard: Sendable { /* ... */ }

@MainActor
public func enumerateMonitors() throws -> [Monitor] { /* ... */ }
```

**Exception**: `postUserEvent()` remains `nonisolated` for background thread posting:

```swift
extension LuminaApp {
    /// Thread-safe user event posting from any thread/actor
    nonisolated func postUserEvent(_ event: UserEvent)
}
```

### 5.2 Internal Synchronization

**User Event Queue** (M0 pattern, unchanged):
```swift
final class UserEventQueue: @unchecked Sendable {
    private var queue: [UserEvent] = []
    private let lock = NSLock()

    func enqueue(_ event: UserEvent) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(event)
    }

    func dequeue() -> UserEvent? {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}
```

**Platform-Specific Thread Safety**:
- **macOS**: NSPasteboard, NSScreen are main-thread-only → @MainActor enforces
- **Windows**: Win32 clipboard API requires OpenClipboard/CloseClipboard serialization → @MainActor enforces
- **X11**: XCB is thread-safe with connection lock (no extra locking needed)
- **Wayland**: wayland-client is not thread-safe → @MainActor enforces

---

## 6. Performance Considerations

### 6.1 Event Loop Optimization

**Zero-Copy Event Translation**:
```swift
// Avoid heap allocations in event loop
mutating func pumpEvents(mode: ControlFlowMode) -> Event? {
    // Stack-allocated event translation
    // Return Event directly (value type, copied to caller's stack)
    return .pointer(.moved(windowID, position: LogicalPosition(x: x, y: y)))
}
```

**Event Queue Sizing**:
- Unbounded queue as per NFR-004a
- Monitor queue depth for diagnostics (future)

**Atom Caching** (X11):
- Cache frequently used atoms at startup → eliminate `xcb_intern_atom` calls in hot path

**Protocol Version Caching** (Wayland):
- Query protocol versions once at init → no runtime checks

### 6.2 DPI/Scaling Conversions

**Inline Conversions**:
```swift
@inline(__always)
public func toPhysical(scaleFactor: Float) -> PhysicalSize {
    PhysicalSize(
        width: Int((width * scaleFactor).rounded()),
        height: Int((height * scaleFactor).rounded())
    )
}
```

**Avoid Redundant Conversions**:
- Store scale factor in window state
- Only convert when rendering or translating platform events

---

## 7. Testing Architecture

### 7.1 Unit Test Additions

```swift
// Tests/LuminaTests/Core/EventTests.swift - [EXTENDED]
@Test("RedrawEvent enum pattern matching")
func testRedrawEvent() {
    let windowID = WindowID(rawValue: 42)
    let rect = LogicalRect(origin: LogicalPosition(x: 0, y: 0),
                           size: LogicalSize(width: 100, height: 100))

    let event = Event.redraw(.requested(windowID, dirtyRect: rect))

    if case .redraw(.requested(let id, let dirtyRect)) = event {
        #expect(id == windowID)
        #expect(dirtyRect == rect)
    } else {
        Issue.record("Event pattern match failed")
    }
}

// Tests/LuminaTests/Core/ControlFlowTests.swift - [NEW]
@Test("Deadline expiration check")
func testDeadlineExpiration() {
    let deadline = ControlFlowMode.Deadline(seconds: 0.1)
    #expect(!deadline.hasExpired)

    Thread.sleep(forTimeInterval: 0.15)
    #expect(deadline.hasExpired)
}

// Tests/LuminaTests/Core/MonitorStructTests.swift - [NEW]
@Test("Monitor struct value semantics")
func testMonitorValueType() {
    let monitor = Monitor(
        id: MonitorID(rawValue: 1),
        name: "Test Monitor",
        position: LogicalPosition(x: 0, y: 0),
        size: LogicalSize(width: 1920, height: 1080),
        workArea: LogicalRect(
            origin: LogicalPosition(x: 0, y: 25),
            size: LogicalSize(width: 1920, height: 1055)
        ),
        scaleFactor: 2.0,
        isPrimary: true
    )

    // Test value type properties (no system calls)
    #expect(monitor.workArea.size.height == 1055)
    #expect(monitor.scaleFactor == 2.0)
    #expect(monitor.isPrimary == true)

    // Test Hashable conformance
    let monitor2 = monitor
    #expect(monitor == monitor2)
    #expect(monitor.hashValue == monitor2.hashValue)
}

// Tests/LuminaTests/Core/CapabilitiesTests.swift - [NEW]
@Test("WindowCapabilities equality")
func testWindowCapabilities() {
    let caps1 = WindowCapabilities(
        supportsTransparency: true,
        supportsAlwaysOnTop: true,
        supportsDecorationToggle: true,
        supportsClientSideDecorations: false
    )

    let caps2 = WindowCapabilities(
        supportsTransparency: true,
        supportsAlwaysOnTop: true,
        supportsDecorationToggle: true,
        supportsClientSideDecorations: false
    )

    #expect(caps1 == caps2)
}
```

### 7.2 Platform-Specific Manual Tests

**Manual Test Checklist Template** (example for Linux X11):

```markdown
# Linux X11 Manual Test Checklist

## Environment
- Distribution: Ubuntu 24.04 LTS
- Desktop: GNOME X11
- DPI: 1.0x (96 DPI)

## Tests
- [ ] Window creation with title "Test Window"
- [ ] Window resize (drag corner)
- [ ] Window move (drag title bar)
- [ ] Mouse click events (left, right, middle)
- [ ] Scroll wheel (vertical, horizontal)
- [ ] Keyboard input (alphanumeric, symbols)
- [ ] Modifier keys (Shift, Ctrl, Alt, Super)
- [ ] Window focus change (Alt+Tab)
- [ ] Clipboard copy from external app, paste in Lumina
- [ ] Clipboard copy from Lumina, paste in external app
- [ ] Monitor enumeration (output monitor list)
- [ ] Toggle decorations (borderless mode)
- [ ] Always-on-top (window stays above others)

## Results
- Passed: X/Y tests
- Failed: Z tests (list failures with details)
```

---

## 8. Documentation Requirements

### 8.1 API Documentation (Constitution Principle I)

**All new public APIs must include**:
- Description of purpose and behavior
- Parameter explanations
- Return value descriptions
- Throws clauses with error cases
- Usage examples

**Example**:
```swift
/// Unified event pump with configurable control flow
///
/// Processes platform events and returns the next Lumina event if available.
/// The control flow mode determines blocking behavior:
/// - `.wait`: Blocks until an event arrives (low power consumption)
/// - `.poll`: Returns immediately after processing available events
/// - `.waitUntil(deadline)`: Blocks until event or deadline expires
///
/// - Parameter mode: Control flow strategy
/// - Returns: Next event if available, `nil` if no events and non-blocking mode
/// - Throws: Never throws (platform errors enqueued as events)
///
/// # Example
/// ```swift
/// var app = try createLuminaApp()
///
/// // Blocking wait for next event
/// while let event = app.pumpEvents(mode: .wait) {
///     handleEvent(event)
/// }
///
/// // Non-blocking poll for animations
/// while running {
///     while let event = app.pumpEvents(mode: .poll) {
///         handleEvent(event)
///     }
///     renderFrame()
/// }
/// ```
@MainActor
mutating func pumpEvents(mode: ControlFlowMode) -> Event?
```

### 8.2 Platform Compatibility Matrix

# Platform Feature Support Matrix

| Feature | macOS | Windows | Linux X11 | Linux Wayland |
|---------|-------|---------|-----------|---------------|
| Window Creation | ✅ | ✅ | ✅ | ✅ |
| Transparency | ✅ | ✅ | ⚠️ | ✅ |
| Always-On-Top | ✅ | ✅ | ✅ | ❌ |
| Decoration Toggle | ✅ | ✅ | ✅ | ⚠️ |
| Clipboard (Text) | ✅ | ✅ | ✅ | ✅ |
| Monitor Enumeration | ✅ | ✅ | ✅ | ✅ |
| Fractional Scaling | ❌ | ✅ | ⚠️ | ⚠️ |
| RedrawRequested Events | ✅ | ⚠️ | ✅ | ✅ |
| Control Flow Modes | ✅ | ⚠️ | ✅ | ✅ |

**Legend**:
- ✅ Fully supported
- ⚠️ Partial support (see notes)
- ❌ Not supported
- *blank* Not implemented in M1

**Notes**:
- **Linux X11 Transparency**: Requires ARGB visual setup (deferred to M2)
- **Linux Wayland Always-On-Top**: No standard protocol (compositor-dependent)
- **Linux Wayland Decoration Toggle**: Requires xdg-decoration protocol (not all compositors)
- **Fractional Scaling (X11)**: Via Xft.dpi configuration (application-level)
- **Fractional Scaling (Wayland)**: Via wp_fractional_scale_v1 protocol (optional)
- **Windows RedrawRequested/Control Flow**: Deferred to M2

---

## 9. Dependency Management

### 9.1 Swift Package Manager Configuration

```swift
// Package.swift
let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v15),    // macOS 15 (Sequoia) minimum
        .windows(.v11),  // Windows 11 minimum
        .linux           // No specific version requirement
    ],
    products: [
        .library(
            name: "Lumina",
            targets: ["Lumina"]
        )
    ],
    targets: [
        // Main library target
        .target(
            name: "Lumina",
            dependencies: [
                .target(name: "CXCBLinux", condition: .when(platforms: [.linux])),
                .target(name: "CWaylandLinux", condition: .when(platforms: [.linux]))
            ],
            path: "Sources/Lumina",
            swiftSettings: [
                .define("LUMINA_X11", .when(platforms: [.linux])),
                .define("LUMINA_WAYLAND", .when(platforms: [.linux]))
            ]
        ),

        // X11 C library bindings
        .systemLibrary(
            name: "CXCBLinux",
            path: "Sources/CInterop/CXCBLinux",
            pkgConfig: "xcb xcb-keysyms xcb-xkb xcb-xinput xkbcommon xkbcommon-x11",
            providers: [
                .apt(["libxcb1-dev", "libxcb-keysyms1-dev", "libxcb-xkb-dev",
                      "libxcb-xinput-dev", "libxkbcommon-dev", "libxkbcommon-x11-dev"]),
                .yum(["libxcb-devel", "libxkbcommon-devel", "libxkbcommon-x11-devel"])
            ]
        ),

        // Wayland C library bindings
        .systemLibrary(
            name: "CWaylandLinux",
            path: "Sources/CInterop/CWaylandLinux",
            pkgConfig: "wayland-client xkbcommon",
            providers: [
                .apt(["libwayland-dev", "libxkbcommon-dev"]),
                .yum(["wayland-devel", "libxkbcommon-devel"])
            ]
        ),

        // Test target
        .testTarget(
            name: "LuminaTests",
            dependencies: ["Lumina"],
            path: "Tests/LuminaTests"
        )
    ]
)
```

### 9.2 Module Maps

```c
// Sources/CInterop/CXCBLinux/module.modulemap
module CXCBLinux {
    header "shims.h"
    link "xcb"
    link "xcb-keysyms"
    link "xcb-xkb"
    link "xcb-xinput"
    link "xkbcommon"
    link "xkbcommon-x11"
    export *
}
```

```c
// Sources/CInterop/CWaylandLinux/module.modulemap
module CWaylandLinux {
    header "shims.h"
    link "wayland-client"
    link "xkbcommon"
    export *
}
```

---

## 10. Build & Deployment

### 10.1 Build Commands

**macOS**:
```bash
swift build -c release
swift test
```

**Linux** (Ubuntu/Debian):
```bash
# Install dependencies
sudo apt install libxcb1-dev libxcb-keysyms1-dev libxcb-xkb-dev \
                 libxcb-xinput-dev libxkbcommon-dev libxkbcommon-x11-dev \
                 libwayland-dev

# Build
swift build -c release

# Test
swift test
```

**Cross-Platform CI**:
- macOS: GitHub Actions (macos-latest)
- Linux: GitHub Actions (ubuntu-24.04)
- Windows: Deferred to M2 (existing M0 implementation unchanged)

---

## 11. Risk Mitigation Strategies

### 11.1 Wayland Protocol Fragmentation

**Detection**:
```swift
struct WaylandProtocols {
    var hasFractionalScale: Bool = false
    var hasXdgDecoration: Bool = false

    init(registry: OpaquePointer) {
        // Query available protocols via wl_registry
        // Set flags based on availability
    }
}
```

**Graceful Degradation**:
```swift
func setDecorated(_ decorated: Bool) throws {
    guard protocols.hasXdgDecoration else {
        throw LuminaError.waylandProtocolMissing(protocol: "xdg-decoration")
    }
    // Proceed with decoration toggle
}
```

### 11.2 X11 Window Manager Quirks

**Compatibility Testing**:
- Test on Mutter (GNOME), KWin (KDE), i3, Openbox
- Document known quirks in compatibility matrix

**Lowest-Common-Denominator Approach**:
- Use universally supported EWMH atoms
- Avoid advanced features with spotty WM support

---

## 12. Success Criteria Checklist

| Criterion | Design Coverage |
|-----------|----------------|
| Cross-Platform API Consistency | ✅ LuminaApp/LuminaWindow protocols extended uniformly |
| Linux X11 Support | ✅ Complete implementation plan |
| Linux Wayland Support | ✅ Complete implementation plan |
| macOS Wave B Features | ✅ Redraw, control flow, decorations, clipboard, monitors |
| Capability Detection | ✅ WindowCapabilities, ClipboardCapabilities, MonitorCapabilities |
| Thread Safety | ✅ @MainActor enforcement, UserEventQueue locks |
| Error Handling | ✅ Typed LuminaError enum, throwing functions |
| Performance Targets | ✅ Zero-copy events, atom caching, inline conversions |
| Testing Strategy | ✅ Unit tests, manual checklists, platform coverage |
| Documentation | ✅ API docs, compatibility matrix, examples |

---

## 13. Open Design Questions

### 13.1 Resolved

- **Backend Selection**: Environment-based (WAYLAND_DISPLAY → Wayland, DISPLAY → X11)
- **Clipboard API**: Synchronous (simpler for M1 text-only)
- **Redraw Strategy**: Hybrid (NSView + CADisplayLink on macOS)
- **Error Handling**: Throwing functions for recoverable errors

### 13.2 Deferred to Implementation

- **XInput2 Setup Details**: Exact API calls for high-precision scrolling
- **Wayland Protocol Bindings**: C interop vs Swift bindings generation
- **fd_set Manipulation**: Swift doesn't expose FD_SET directly (need C shim)
- **CADisplayLink Integration**: Exact frame pacing synchronization

---

## 14. Next Steps

### 14.1 Phase 2: Task Generation

The `/tasks` command will generate ordered, actionable tasks from this design:

1. **Core Type Extensions** (4-6 tasks)
   - Extend Event enum with RedrawEvent, MonitorEvent
   - Implement ControlFlowMode enum and Deadline
   - Implement Monitor struct and enumeration API
   - Implement Clipboard API
   - Implement Capabilities structs
   - Extend LuminaError enum

2. **macOS Wave B Implementation** (6-8 tasks)
   - Extend MacApplication with pumpEvents()
   - Implement MacWindow decoration methods
   - Implement MacClipboard
   - Implement MacMonitor enumeration
   - Add redraw request tracking
   - Implement monitor change notifications

3. **Linux X11 Implementation** (10-12 tasks)
   - Create C interop module (CXCBLinux)
   - Implement X11Atoms caching
   - Implement X11Application event loop
   - Implement X11Window
   - Implement X11Input translation
   - Implement X11Monitor enumeration
   - Implement X11Clipboard
   - Implement X11Capabilities

4. **Linux Wayland Implementation** (10-12 tasks)
   - Create C interop module (CWaylandLinux)
   - Implement WaylandProtocols detection
   - Implement WaylandApplication event loop
   - Implement WaylandWindow
   - Implement WaylandInput translation
   - Implement WaylandMonitor enumeration
   - Implement WaylandClipboard
   - Implement WaylandCapabilities

5. **Testing** (8-10 tasks)
   - Write unit tests for new core types
   - Write macOS Wave B platform tests
   - Write Linux X11 platform tests
   - Write Linux Wayland platform tests
   - Create manual test checklists

6. **Documentation** (4-6 tasks)
   - Document new APIs with examples
   - Update platform compatibility matrix
   - Write migration guide (M0 → M1)
   - Create example applications

**Estimated Total**: 40-50 tasks

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
**Design Status**: ✅ Complete - Ready for Phase 2 Task Planning
