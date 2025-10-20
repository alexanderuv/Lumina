# Design Document: Milestone 0 - Wave A Core Windowing & Input

**Date**: 2025-10-04
**Status**: Draft
**Based on**: research.md, spec.md, constitution.md

---

## Architecture Overview

### Module Hierarchy

```
┌─────────────────────────────────────────────┐
│           Application Layer                  │
│   (HelloWindow, InputExplorer, ScalingDemo)  │
└─────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│            Lumina (Public API)               │
│  Cross-platform abstractions & contracts     │
│  - Application, Window, Events               │
│  - Geometry types (LogicalSize, Physical)    │
│  - Cursor, Input                             │
└─────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌──────────────────┐    ┌──────────────────┐
│ LuminaPlatformMac│    │ LuminaPlatformWin│
│  (macOS Backend) │    │ (Windows Backend)│
│  - AppKit/Cocoa  │    │  - Win32 API     │
│  - CFRunLoop     │    │  - Message Pump  │
└──────────────────┘    └──────────────────┘
        │                         │
        ▼                         ▼
┌──────────────────┐    ┌──────────────────┐
│   macOS APIs     │    │   Windows APIs   │
│ NSWindow, NSEvent│    │  HWND, WM_*      │
└──────────────────┘    └──────────────────┘
```

### Design Principles

1. **Protocol-Oriented Design**: Core abstractions are protocols, platform backends are concrete implementations
2. **Value Semantics**: Events, geometry types are immutable structs (Sendable, borrowable)
3. **Compile-Time Platform Selection**: No runtime branching, platform code selected at build time
4. **Zero-Cost Abstractions**: Protocol witnesses inlined, borrowing eliminates ARC overhead
5. **Strict Concurrency**: @MainActor isolation, Sendable conformance, compile-time thread safety

---

## Type System Design

### Core Public Types (Lumina)

#### 1. Application

**Purpose**: Event loop manager and application lifecycle controller

```swift
@MainActor
public struct Application: ~Copyable {
    // Private platform backend (type-erased or generic)
    private var backend: any EventLoopBackend

    /// Create a new application instance
    /// - Throws: `LuminaError.platformError` if initialization fails
    public init() throws

    /// Run the event loop until quit (blocking)
    /// - Throws: `LuminaError.platformError` if event loop fails
    public mutating func run() throws

    /// Poll for events without blocking
    /// - Returns: `true` if events were processed, `false` if queue is empty
    /// - Throws: `LuminaError.platformError` if polling fails
    public mutating func poll() throws -> Bool

    /// Wait for the next event (low-power sleep)
    /// - Throws: `LuminaError.platformError` if wait fails
    public mutating func wait() throws

    /// Post a custom user event to the event queue (thread-safe)
    /// - Parameter event: The user event to post
    public func postUserEvent(_ event: UserEvent)

    /// Request application termination
    public func quit()
}
```

**Ownership**: `~Copyable` ensures single instance (no accidental duplication)

**Thread Safety**: @MainActor isolated, `postUserEvent` is thread-safe via internal synchronization

---

#### 2. Window

**Purpose**: Platform window abstraction with lifecycle and attribute management

```swift
@MainActor
public struct Window: Identifiable, ~Copyable {
    public let id: WindowID

    /// Create a new window
    /// - Parameters:
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether window can be resized
    /// - Returns: Result containing Window or LuminaError
    public static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool = true
    ) -> Result<Window, LuminaError>

    /// Show the window
    public mutating func show()

    /// Hide the window
    public mutating func hide()

    /// Close the window (consumes self)
    public consuming func close()

    /// Set window title
    public mutating func setTitle(_ title: borrowing String)

    /// Get current window size (logical coordinates)
    public borrowing func size() -> LogicalSize

    /// Resize window programmatically
    public mutating func resize(_ size: borrowing LogicalSize)

    /// Get window position (screen coordinates)
    public borrowing func position() -> LogicalPosition

    /// Move window to new position
    public mutating func moveTo(_ position: borrowing LogicalPosition)

    /// Set minimum window size constraint
    public mutating func setMinSize(_ size: borrowing LogicalSize?)

    /// Set maximum window size constraint
    public mutating func setMaxSize(_ size: borrowing LogicalSize?)

    /// Request focus for this window
    public mutating func requestFocus()

    /// Get current scale factor (DPI)
    public borrowing func scaleFactor() -> Float
}
```

**Ownership**: `~Copyable` prevents window handle duplication, `consuming func close()` ensures proper cleanup

---

#### 3. Events

**Purpose**: Unified event type hierarchy for all system and user events

```swift
/// Main event enum (Sendable for thread-safe passing)
public enum Event: Sendable {
    case window(WindowEvent)
    case pointer(PointerEvent)
    case keyboard(KeyboardEvent)
    case user(UserEvent)
}

/// Window lifecycle and state events
public enum WindowEvent: Sendable {
    case created(WindowID)
    case closed(WindowID)
    case resized(WindowID, LogicalSize)
    case moved(WindowID, LogicalPosition)
    case focused(WindowID)
    case unfocused(WindowID)
    case scaleFactorChanged(WindowID, oldFactor: Float, newFactor: Float)
}

/// Pointer (mouse/trackpad) events
public enum PointerEvent: Sendable {
    case moved(WindowID, position: LogicalPosition)
    case entered(WindowID)
    case left(WindowID)
    case buttonPressed(WindowID, button: MouseButton, position: LogicalPosition)
    case buttonReleased(WindowID, button: MouseButton, position: LogicalPosition)
    case wheel(WindowID, deltaX: Float, deltaY: Float)
}

/// Mouse button enumeration
public enum MouseButton: Sendable {
    case left
    case right
    case middle
}

/// Keyboard events
public enum KeyboardEvent: Sendable {
    case keyDown(WindowID, key: KeyCode, modifiers: ModifierKeys)
    case keyUp(WindowID, key: KeyCode, modifiers: ModifierKeys)
    case textInput(WindowID, text: String)  // UTF-8 text for Latin layouts
}

/// Physical key codes (platform-normalized)
public struct KeyCode: Sendable, Hashable {
    // Normalized scan codes (consistent across platforms)
    let rawValue: UInt32
}

/// Modifier key state (bitfield)
public struct ModifierKeys: OptionSet, Sendable {
    public let rawValue: UInt8

    public static let shift   = ModifierKeys(rawValue: 1 << 0)
    public static let control = ModifierKeys(rawValue: 1 << 1)
    public static let alt     = ModifierKeys(rawValue: 1 << 2)
    public static let command = ModifierKeys(rawValue: 1 << 3)  // Cmd on macOS, Win on Windows
}

/// User-defined events (thread-safe posting)
public struct UserEvent: Sendable {
    public let data: Any  // Sendable-constrained in practice

    public init<T: Sendable>(_ data: T)
}
```

**Design Notes**:
- All event types are value types (structs/enums) for performance
- Sendable conformance enables cross-thread event passing
- Borrowing semantics during dispatch (no copying)
- WindowID associates events with specific windows

---

#### 4. Geometry Types

**Purpose**: Type-safe coordinate and size handling with DPI awareness

```swift
/// Logical (device-independent) size in points
public struct LogicalSize: Sendable, Hashable {
    public let width: Float
    public let height: Float

    public init(width: Float, height: Float)

    /// Convert to physical pixels using scale factor
    public func toPhysical(scaleFactor: Float) -> PhysicalSize {
        PhysicalSize(
            width: Int(width * scaleFactor),
            height: Int(height * scaleFactor)
        )
    }
}

/// Physical (pixel) size
public struct PhysicalSize: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int)

    /// Convert to logical points using scale factor
    public func toLogical(scaleFactor: Float) -> LogicalSize {
        LogicalSize(
            width: Float(width) / scaleFactor,
            height: Float(height) / scaleFactor
        )
    }
}

/// Logical position in screen coordinates
public struct LogicalPosition: Sendable, Hashable {
    public let x: Float
    public let y: Float

    public init(x: Float, y: Float)

    public func toPhysical(scaleFactor: Float) -> PhysicalPosition
}

/// Physical position in pixel coordinates
public struct PhysicalPosition: Sendable, Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int)

    public func toLogical(scaleFactor: Float) -> LogicalPosition
}
```

**Design Notes**:
- Distinct types prevent coordinate mixing bugs
- Conversion is explicit and requires scale factor
- Value types with borrowing for zero-copy passing
- Float for logical (matches platform APIs), Int for physical (actual pixels)

---

#### 5. Cursor

**Purpose**: System cursor appearance and visibility control

```swift
@MainActor
public struct Cursor {
    /// Standard system cursor types
    public enum SystemCursor: Sendable {
        case arrow
        case ibeam         // Text selection
        case crosshair
        case hand          // Pointer/link
        case resizeNS      // North-South resize
        case resizeEW      // East-West resize
        case resizeNESW    // Diagonal resize
        case resizeNWSE    // Diagonal resize
    }

    /// Set the current cursor appearance
    public static func set(_ cursor: SystemCursor)

    /// Hide the cursor
    public static func hide()

    /// Show the cursor
    public static func show()
}
```

**Design Notes**:
- Static methods (global cursor state per window)
- @MainActor isolated (UI operation)
- M0 supports system cursors only (custom cursors in Wave B)

---

#### 6. Error Types

**Purpose**: Explicit error handling per constitution requirements

```swift
/// Lumina error types
public enum LuminaError: Error, Sendable {
    /// Window creation or operation failed
    case windowCreationFailed(reason: String)

    /// Platform-specific error (wraps OS error)
    case platformError(code: Int, message: String)

    /// Invalid API usage (programmer error)
    case invalidState(String)

    /// Event loop error
    case eventLoopFailed(reason: String)
}
```

---

### Platform Backend Protocol

**Internal protocol** (not part of public API):

```swift
/// Platform-specific event loop implementation
internal protocol EventLoopBackend: Sendable {
    /// Run event loop until quit (blocking)
    mutating func run() throws

    /// Poll for events without blocking
    mutating func poll() throws -> Bool

    /// Wait for next event (low-power sleep)
    mutating func wait() throws

    /// Post user event to queue (thread-safe)
    func postUserEvent(_ event: UserEvent)

    /// Request event loop termination
    func quit()
}

/// Platform-specific window backend
internal protocol WindowBackend: Sendable {
    var id: WindowID { get }

    mutating func show()
    mutating func hide()
    consuming func close()

    mutating func setTitle(_ title: borrowing String)
    borrowing func size() -> LogicalSize
    mutating func resize(_ size: borrowing LogicalSize)

    borrowing func position() -> LogicalPosition
    mutating func moveTo(_ position: borrowing LogicalPosition)

    mutating func setMinSize(_ size: borrowing LogicalSize?)
    mutating func setMaxSize(_ size: borrowing LogicalSize?)

    mutating func requestFocus()
    borrowing func scaleFactor() -> Float
}
```

---

## Platform-Specific Implementation Strategy

### Platform-Specific Edge Case Behaviors

**Resize Constraints (min/max size)**:
- **macOS**: NSWindow enforces constraints automatically; resize operations are clipped to valid range
- **Windows**: WM_GETMINMAXINFO enforces constraints; resize attempts beyond limits are blocked by OS

**Event Flooding (high-frequency input)**:
- **macOS**: NSEvent coalescing may occur; rapid mouse moves are merged by AppKit
- **Windows**: Message queue may drop events under extreme load (>1000 events/sec); OS handles throttling

**Focus Loss / Minimization**:
- **macOS**: NSWindow delegate receives resignKey/willMiniaturize notifications; app continues running
- **Windows**: WM_KILLFOCUS / WM_SIZE(SIZE_MINIMIZED) messages delivered; app remains responsive

**Event Ordering (simultaneous inputs)**:
- **macOS**: NSEvent ordering determined by CFRunLoop priority; keyboard events typically precede mouse
- **Windows**: Message pump ordering determined by GetMessage sequence; platform-dependent priority

### macOS Backend (LuminaPlatformMac)

#### MacApplication (EventLoopBackend)

```swift
@MainActor
internal struct MacApplication: EventLoopBackend {
    private var runLoop: CFRunLoop
    private var shouldQuit: Bool = false
    private var eventQueue: [Event] = []  // User event queue (synchronized)

    init() throws {
        self.runLoop = CFRunLoopGetCurrent()
        // Initialize AppKit if needed
    }

    mutating func run() throws {
        while !shouldQuit {
            // Process NSEvents via NSApp.nextEvent
            if let nsEvent = NSApp.nextEvent(
                matching: .any,
                until: .distantFuture,
                inMode: .default,
                dequeue: true
            ) {
                processNSEvent(nsEvent)
            }
        }
    }

    mutating func poll() throws -> Bool {
        guard let nsEvent = NSApp.nextEvent(
            matching: .any,
            until: .distantPast,  // Non-blocking
            inMode: .default,
            dequeue: true
        ) else {
            return false
        }

        processNSEvent(nsEvent)
        return true
    }

    mutating func wait() throws {
        // Use CFRunLoop for low-power wait
        CFRunLoopRunInMode(.defaultMode, .infinity, true)
    }

    func postUserEvent(_ event: UserEvent) {
        // Thread-safe enqueue (use synchronization)
        // Post NSEvent to wake up run loop
    }

    private func processNSEvent(_ nsEvent: NSEvent) {
        // Translate NSEvent to Lumina Event
        // Dispatch to appropriate handler
    }
}
```

**Key Details**:
- Uses `NSApp.nextEvent` for event pump
- CFRunLoop integration for `wait` mode (low power)
- NSEvent → Lumina Event translation
- Coordinate system: AppKit uses bottom-left origin, normalize to top-left

---

#### MacWindow (WindowBackend)

```swift
@MainActor
internal struct MacWindow: WindowBackend {
    let id: WindowID
    private var nsWindow: NSWindow

    static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool
    ) -> Result<MacWindow, LuminaError> {
        let contentRect = NSRect(
            x: 0, y: 0,
            width: CGFloat(size.width),
            height: CGFloat(size.height)
        )

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable {
            styleMask.insert(.resizable)
        }

        let nsWindow = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        nsWindow.title = title

        return .success(MacWindow(id: WindowID(), nsWindow: nsWindow))
    }

    mutating func show() {
        nsWindow.makeKeyAndOrderFront(nil)
    }

    mutating func hide() {
        nsWindow.orderOut(nil)
    }

    borrowing func scaleFactor() -> Float {
        Float(nsWindow.backingScaleFactor)
    }

    // ... other protocol methods
}
```

**Key Details**:
- Wraps NSWindow with platform-agnostic API
- Scale factor from `backingScaleFactor` (Retina support)
- Coordinate conversion (AppKit origin = bottom-left)

---

### Windows Backend (LuminaPlatformWin)

#### WinApplication (EventLoopBackend)

```swift
@MainActor
internal struct WinApplication: EventLoopBackend {
    private var shouldQuit: Bool = false

    init() throws {
        // Initialize COM for DPI awareness
        // SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)
    }

    mutating func run() throws {
        var msg = MSG()
        while GetMessage(&msg, nil, 0, 0) > 0 {
            TranslateMessage(&msg)
            DispatchMessage(&msg)
        }
    }

    mutating func poll() throws -> Bool {
        var msg = MSG()
        if PeekMessage(&msg, nil, 0, 0, PM_REMOVE) != 0 {
            TranslateMessage(&msg)
            DispatchMessage(&msg)
            return true
        }
        return false
    }

    mutating func wait() throws {
        WaitMessage()  // Low-power sleep until next message
    }

    func postUserEvent(_ event: UserEvent) {
        // PostMessage with custom WM_USER message
    }
}
```

**Key Details**:
- Win32 message pump (GetMessage/PeekMessage/DispatchMessage)
- WaitMessage for low-power wait mode
- DPI awareness set at process startup
- WM_* message → Lumina Event translation

---

#### WinWindow (WindowBackend)

```swift
@MainActor
internal struct WinWindow: WindowBackend {
    let id: WindowID
    private var hwnd: HWND

    static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool
    ) -> Result<WinWindow, LuminaError> {
        let dwStyle: DWORD = resizable
            ? (WS_OVERLAPPEDWINDOW)
            : (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU)

        let hwnd = CreateWindowEx(
            0,                          // dwExStyle
            className,                  // Window class
            title.utf16CString,         // Window title
            dwStyle,
            CW_USEDEFAULT, CW_USEDEFAULT,
            Int32(size.width), Int32(size.height),
            nil, nil, hInstance, nil
        )

        guard hwnd != nil else {
            return .failure(.windowCreationFailed(reason: "CreateWindowEx failed"))
        }

        return .success(WinWindow(id: WindowID(), hwnd: hwnd))
    }

    borrowing func scaleFactor() -> Float {
        let dpi = GetDpiForWindow(hwnd)
        return Float(dpi) / 96.0  // 96 DPI = 100% scale
    }

    // ... other protocol methods
}
```

**Key Details**:
- HWND wrapper with Win32 API calls
- DPI from `GetDpiForWindow` (per-monitor awareness)
- Window styles for resizable/non-resizable
- Coordinate system: origin top-left (matches macOS normalization)

---

## Thread Safety and Concurrency Model

### Main Actor Isolation

All UI operations are `@MainActor` isolated:

```swift
@MainActor
func example() {
    var app = Application()  // OK - on main actor
    app.run()                // OK - on main actor
}

// Background thread:
Task.detached {
    var app = Application()  // ERROR - @MainActor isolation violated
}
```

### Cross-Thread Communication

Background threads post user events (thread-safe):

```swift
@MainActor
var app = Application()

Task.detached {
    // Compute something expensive
    let result = heavyComputation()

    // Post result to main thread
    app.postUserEvent(UserEvent(result))  // Thread-safe
}

// Main thread receives event in event loop
```

---

## Memory Management Patterns

### Borrowing for Event Dispatch

Events are dispatched using `borrowing` to eliminate ARC overhead:

```swift
func handleEvent(_ event: borrowing Event) {
    switch event {
    case .pointer(let pointerEvent):
        handlePointer(borrowing: pointerEvent)  // No copy, no ARC
    case .keyboard(let keyEvent):
        handleKeyboard(borrowing: keyEvent)    // No copy, no ARC
    default:
        break
    }
}
```

**Performance Benefit**:
- Zero retain/release cycles during dispatch
- Hot path optimized for <2ms latency requirement

### When ARC is Required

ARC is used for:
1. Closures capturing window state (documented justification)
2. Platform API callbacks (NSEvent handlers, WndProc)
3. Async task contexts

Example with justification:

```swift
// ARC required: Closure captures window for async callback
window.onResize { [weak self] newSize in
    // ARC overhead acceptable: resize is infrequent (not hot path)
    self?.handleResize(newSize)
}
```

---

## Error Handling Patterns

### Window Creation (Recoverable Error)

```swift
let result = Window.create(title: "App", size: LogicalSize(width: 800, height: 600))

switch result {
case .success(let window):
    window.show()
case .failure(let error):
    print("Failed to create window: \(error)")
    // Graceful degradation or retry
}
```

### Event Loop Errors (Typed Throws)

```swift
do {
    try app.run()
} catch let error as LuminaError {
    switch error {
    case .eventLoopFailed(let reason):
        print("Event loop crashed: \(reason)")
    default:
        print("Unexpected error: \(error)")
    }
}
```

---

## Performance Considerations

### Event Dispatch Latency (<2ms)

Optimizations:
1. **Borrowing semantics**: No ARC overhead in hot path
2. **Value types**: Stack allocation, no heap
3. **Inline protocol witnesses**: Compiler devirtualization
4. **Platform-native event loop**: No abstraction overhead

### Window Creation (<100ms)

Platform-specific:
- macOS: NSWindow creation is fast (native API)
- Windows: CreateWindowEx requires window class registration (one-time cost)

### Memory Efficiency

- Events are stack-allocated (no heap)
- Window state is minimal (platform handle + metadata)
- No global state (Application owns event loop)

---

## Public API Surface

### Exported Symbols (Lumina)

```swift
// Types
public struct Application
public struct Window
public enum Event
public struct LogicalSize, PhysicalSize
public struct LogicalPosition, PhysicalPosition
public struct KeyCode, ModifierKeys
public enum MouseButton
public struct Cursor

// Errors
public enum LuminaError

// Protocols (if needed for extensibility)
// (None in M0 - internal use only)
```

### API Guarantees

1. **Stability**: No breaking changes without RFC
2. **Documentation**: All public symbols have complete docs
3. **Thread Safety**: Explicit @MainActor or Sendable
4. **Error Handling**: Result types or typed throws

---

## Documentation Structure

### API Reference

Generated from inline documentation:

```swift
/// Creates a new application instance.
///
/// The application manages the event loop and window lifecycle.
/// Only one application instance should exist per process.
///
/// - Throws: `LuminaError.platformError` if platform initialization fails
///
/// - Example:
///   ```swift
///   let app = try Application()
///   try app.run()
///   ```
@MainActor
public struct Application {
    // ...
}
```

### User Guides

1. **Getting Started**: Hello Window tutorial
2. **Event Handling**: Input Explorer walkthrough (demonstrates async/await event handling by dispatching events to async functions)
3. **DPI/Scaling**: Scaling Demo explanation
4. **Platform Notes**: macOS vs Windows differences

---

## Testing Strategy

### Unit Tests (LuminaTests)

```swift
import Testing
@testable import Lumina

@Suite("Event Loop State Machine")
struct EventLoopTests {
    @Test("Application initializes successfully")
    func testInit() async throws {
        let app = try Application()
        // Assert app state
    }

    @Test("Poll returns false on empty queue")
    func testPollEmpty() async throws {
        var app = try Application()
        let hasEvents = try app.poll()
        #expect(hasEvents == false)
    }
}
```

### Platform-Specific Tests

macOS-only:

```swift
#if os(macOS)
@Suite("macOS Backend")
struct MacPlatformTests {
    @Test("NSWindow scale factor matches display")
    func testScaleFactor() async throws {
        // ...
    }
}
#endif
```

### Platform-Specific Tests (Event Sequences)

Test event sequences and cross-platform parity (platform-specific because requires actual window creation):

```swift
#if os(macOS)
@Test("Mouse move event sequence on macOS")
func testMouseMoveSequenceMac() async throws {
    // Create actual NSWindow
    // Test mouse move → button press → release sequence
    // Verify event ordering
}
#endif

#if os(Windows)
@Test("Mouse move event sequence on Windows")
func testMouseMoveSequenceWin() async throws {
    // Create actual HWND window
    // Test mouse move → button press → release sequence
    // Verify event ordering matches macOS
}
#endif
```

**Note**: Per constitution, these are platform-specific tests, not integration tests. All windowing tests require actual window creation and are therefore platform-dependent.

---

## Migration Path (Future Waves)

### Wave B Extensions

- Window decorations (will extend Window API)
- Clipboard support (new Clipboard type)
- Monitor enumeration (new Monitor API)

**Compatibility**: All Wave A APIs remain stable, new features are additive

---

## Summary

This design provides:

1. ✅ **Type-safe cross-platform abstraction** (LogicalSize/PhysicalSize prevents bugs)
2. ✅ **Performance-optimized event dispatch** (borrowing semantics, <2ms latency)
3. ✅ **Constitutional compliance** (Swift 6.2+, Swift Testing, borrowing ownership)
4. ✅ **Platform parity** (macOS + Windows with identical behavior)
5. ✅ **Extensibility** (protocol-based backends, additive API evolution)

Ready for Phase 2 (Task Planning).
