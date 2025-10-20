# Research: Milestone 0 - Wave A Core Windowing & Input

**Date**: 2025-10-04
**Scope**: Platform integration patterns, Swift 6.2+ concurrency, performance optimization

---

## Research Areas

### 1. Cross-Platform Event Loop Abstraction

**Decision**: Protocol-based abstraction with platform-specific implementations

**Rationale**:
- Swift protocols with associated types provide zero-cost abstraction
- Each platform (macOS CFRunLoop, Windows message pump) has fundamentally different semantics
- Protocol allows unified API surface while preserving platform-native behavior
- Supports three modes: `run` (blocking), `poll` (non-blocking), `wait` (low-power)

**Alternatives Considered**:
- C-style function pointers: Rejected due to lack of type safety and Swift 6 concurrency violations
- Grand Central Dispatch (GCD) wrapper: Rejected because it doesn't map cleanly to Windows message pumps and adds unnecessary abstraction overhead
- Callback-based API: Rejected due to ARC overhead and complexity in error handling

**Implementation Approach**:
```swift
protocol EventLoopBackend: Sendable {
    mutating func run() throws
    mutating func poll() throws -> Bool
    mutating func wait() throws
    func postUserEvent(_ event: Event) throws
}
```

**Key References**:
- winit (Rust): Cross-platform event loop patterns
- SDL2: Platform abstraction layer design
- Swift Concurrency SE-0306: Actors and structured concurrency

---

### 2. DPI/Scaling Handling

**Decision**: Distinct value types `LogicalSize` and `PhysicalSize` with explicit conversion APIs

**Rationale**:
- Type safety prevents mixing device-independent and pixel coordinates
- macOS uses logical coordinates (points) by default, Windows uses physical (pixels)
- Scale factor can change at runtime (monitor changes, system settings)
- Swift value semantics ensure no accidental aliasing

**Alternatives Considered**:
- Single `Size` type with flag: Rejected due to runtime errors from flag misuse
- Implicit conversion: Rejected because it hides scaling bugs
- CGFloat-based generics: Rejected due to complexity and loss of semantic meaning

**Implementation Approach**:
```swift
struct LogicalSize: Sendable {
    let width: Float
    let height: Float

    func toPhysical(scaleFactor: Float) -> PhysicalSize
}

struct PhysicalSize: Sendable {
    let width: Int
    let height: Int

    func toLogical(scaleFactor: Float) -> LogicalSize
}
```

**Key References**:
- macOS HIG: Points vs Pixels
- Windows High DPI documentation
- Chrome/Electron: Multi-monitor DPI handling

---

### 3. Borrowing Ownership for Performance

**Decision**: Use `borrowing` and `consuming` parameter modifiers for event handling hot paths

**Rationale**:
- Event dispatch is performance-critical (<2ms latency requirement)
- Borrowing eliminates retain/release cycles for event objects
- Events are read-only during dispatch (no mutation needed)
- Value types with borrowing avoid heap allocation entirely

**Alternatives Considered**:
- Traditional ARC with class types: Rejected due to heap allocation overhead
- Copy-on-write (CoW) semantics: Rejected because events are never modified
- Unsafe pointers: Rejected due to safety concerns and constitution violations

**Implementation Approach**:
```swift
func dispatchEvent(_ event: borrowing Event) {
    // No ARC overhead, event is borrowed for duration of call
    switch event {
    case .pointer(let pointerEvent):
        handlePointer(borrowing: pointerEvent)
    case .keyboard(let keyEvent):
        handleKeyboard(borrowing: keyEvent)
    }
}
```

**Key References**:
- Swift Evolution SE-0377: Borrowing and consuming parameters
- Swift Performance: Understanding ownership
- Benchmarks: ARC overhead in tight loops

---

### 4. Platform-Specific Integration

**Decision**: Conditional compilation with `#if os(macOS)` / `#if os(Windows)` for backend selection

**Rationale**:
- Swift Package Manager supports platform-specific targets
- Compile-time selection eliminates runtime branching
- Each platform gets optimized code path
- No dynamic linking overhead

**Alternatives Considered**:
- Runtime plugin system: Rejected due to dynamic linking overhead and complexity
- Shared backend with runtime checks: Rejected due to binary size and dead code
- Separate packages per platform: Rejected due to maintenance burden

**Platform-Specific Considerations**:

**macOS (AppKit/Cocoa)**:
- Use `CFRunLoop` for `wait` mode (integrates with system power management)
- `NSEvent` translation to platform-agnostic event types
- Automatic DPI scaling via backing store scale factor
- Coordinate system: origin top-left (differs from UIKit)

**Windows (Win32 API)**:
- `GetMessage`/`PeekMessage` for blocking/polling
- `WaitMessage` for low-power wait mode
- Manual DPI awareness via `SetProcessDpiAwareness`
- Coordinate system: origin top-left (matches macOS)
- COM initialization required for some APIs

**Key References**:
- Swift on Windows: Platform support documentation
- AppKit Event Handling Guide
- Windows Desktop Application Development

---

### 5. Error Handling Strategy

**Decision**: `Result<T, LuminaError>` for recoverable errors, `throws` for programmer errors

**Rationale**:
- Window creation can fail (out of memory, invalid parameters)
- Event loop errors are rare but must be explicit
- Constitution requires "explicit Result types or typed exceptions"
- Swift 6 typed throws provides clear error paths

**Alternatives Considered**:
- Optionals: Rejected due to loss of error information
- Fatal errors: Rejected because window creation failures should be recoverable
- Error codes (C-style): Rejected due to type unsafety

**Implementation Approach**:
```swift
enum LuminaError: Error, Sendable {
    case windowCreationFailed(String)
    case platformError(String)
    case invalidState(String)
}

func createWindow(title: String) -> Result<Window, LuminaError>
```

**Key References**:
- Swift Error Handling Best Practices
- Result type patterns in Swift
- Platform API error codes (macOS/Windows)

---

### 6. Threading Model Enforcement

**Decision**: `@MainActor` isolation for all UI APIs, compile-time enforcement via Swift concurrency

**Rationale**:
- Constitution mandates single-threaded UI event loop
- Swift 6 strict concurrency detects violations at compile time
- Background threads communicate via user events (thread-safe queue)
- `@MainActor` is explicit and self-documenting

**Alternatives Considered**:
- Runtime thread checks: Rejected because compile-time is safer
- Manual locks: Rejected due to deadlock risk and performance overhead
- Free-threaded API: Rejected due to platform constraints (AppKit/Win32 are single-threaded)

**Implementation Approach**:
```swift
@MainActor
public struct Application {
    public func run() throws { }
    public func poll() throws -> Bool { }
    public func wait() throws { }
}

// Background tasks post events:
extension Application {
    public func postUserEvent(_ event: Event) {
        // Thread-safe queue internally
    }
}
```

**Key References**:
- Swift Concurrency: @MainActor documentation
- SE-0316: Global actors
- Platform threading constraints (NSRunLoop, Win32 message pump)

---

### 7. Testing Strategy (Swift Testing Framework)

**Decision**: Swift Testing for all tests (unit, integration, platform-specific)

**Rationale**:
- Constitution prohibits XCTest
- Swift Testing supports async/await natively
- Better diagnostics and parameterized tests
- Modern Swift 6 integration

**Test Coverage Approach**:
- **Unit tests**: Discrete components (geometry conversions, event type creation, error handling)
- **Platform-specific tests**: Window creation, event handling, event sequences, cross-platform parity verification (macOS and Windows)
- **Stability tests**: 24-hour idle loop (memory leak detection)
- **Note**: No separate "integration tests" - all windowing tests are platform-dependent per constitution

**Mocking Strategy**:
- Platform backends are protocol-based, allowing mock implementations
- Test doubles for window system calls (no real windows in CI)

**Alternatives Considered**:
- XCTest: Prohibited by constitution
- Manual testing only: Rejected because automated tests catch regressions faster
- Traditional integration tests: Not applicable - all windowing tests are platform-dependent

**Key References**:
- Swift Testing framework documentation
- Event sequence testing patterns
- Virtualized display testing on CI (Xvfb for Linux, headless Windows)

---

### 8. Swift 6.2+ Modern Idioms

**Decision**: Strict concurrency, result builders for declarative window configuration (future), Sendable conformance

**Rationale**:
- Constitution mandates Swift 6.2+ features
- Strict concurrency catches data races at compile time
- Sendable ensures safe cross-boundary data passing
- Modern APIs are more maintainable long-term

**Specific Features**:
- `@MainActor` for UI isolation
- `Sendable` for all event types (value semantics)
- `borrowing`/`consuming` for ownership clarity
- Typed throws (future Swift feature)

**Alternatives Considered**:
- Swift 5.x compatibility: Rejected per constitution
- Unsafe constructs: Only where justified and documented

**Key References**:
- Swift 6 Migration Guide
- Strict concurrency best practices
- Sendable conformance requirements

---

## Summary of Decisions

| Area | Decision | Key Benefit |
|------|----------|-------------|
| Event Loop | Protocol-based abstraction | Zero-cost, platform-native behavior |
| DPI Scaling | Distinct LogicalSize/PhysicalSize types | Type safety, prevents coordinate bugs |
| Performance | Borrowing ownership model | Eliminates ARC overhead (<2ms dispatch) |
| Platform Code | Compile-time conditional compilation | Optimized per-platform binaries |
| Error Handling | Result types for recoverable errors | Explicit error paths, type-safe |
| Threading | @MainActor enforcement | Compile-time safety, clear contracts |
| Testing | Swift Testing framework only | Modern async support, better diagnostics |
| Swift Features | Swift 6.2+ strict concurrency | Data race safety, maintainability |

---

## Open Questions Resolved

- **Q**: How to handle platform differences in event ordering?
  - **A**: Platform abstraction guarantees identical ordering at Lumina API level, backends normalize platform behavior

- **Q**: Can we avoid Objective-C bridging entirely?
  - **A**: Yes - use Swift-native APIs where possible, unsafe pointers for Win32 FFI (documented justification)

- **Q**: What's the best approach for CI testing without physical displays?
  - **A**: Use headless testing infrastructure (macOS virtual framebuffer, Windows Server with virtual display driver)

---

## Next Steps (Phase 1)

Based on research findings, Phase 1 (Design) will specify:
1. Detailed type system (protocols, structs, enums)
2. Module boundaries and dependencies
3. Platform backend implementation strategy
4. Event dispatch architecture
5. Memory management patterns (borrowing vs. ARC)
6. Public API surface with documentation structure

---

*Research complete. All Technical Context areas resolved. Ready for Phase 1 (Design).*
