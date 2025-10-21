# Feature Specification: Milestone 1 Implementation - Linux Support & macOS Enhancements

**Feature Branch**: `002-milestone-1-impl`
**Created**: 2025-10-20
**Status**: Draft
**Input**: User description: "Milestone 1 impl: Use context and functional requirements from docs/plan/milestones/M1.md"

## Execution Flow (main)
```
1. Parse user description from Input
   → If empty: ERROR "No feature description provided"
2. Extract key concepts from description
   → Identify: actors, actions, data, constraints
3. For each unclear aspect:
   → Mark with [NEEDS CLARIFICATION: specific question]
4. Fill User Scenarios & Testing section
   → If no clear user flow: ERROR "Cannot determine user scenarios"
5. Generate Functional Requirements
   → Each requirement must be testable
   → Mark ambiguous requirements
6. Identify Key Entities (if data involved)
7. Run Review Checklist
   → If any [NEEDS CLARIFICAVTION]: WARN "Spec has uncertainties"
   → If implementation details found: ERROR "Remove tech details"
8. Return: SUCCESS (spec ready for planning)
```

---

## ⚡ Quick Guidelines
- ✅ Focus on WHAT users need and WHY
- ❌ Avoid HOW to implement (no tech stack, APIs, code structure)
- 👥 Written for business stakeholders, not developers

---

## Clarifications

### Session 2025-10-20
- Q: For event delivery (FR-004 "deterministic order"), what is the acceptable maximum latency from OS event generation to application callback? → A: < 1ms (hard real-time gaming/CAD applications)
- Q: What is the maximum number of concurrent windows that must be supported per application instance? → A: Unlimited (bounded only by system memory)
- Q: What level of diagnostic logging/telemetry should the framework provide for debugging and monitoring? → A: Configurable levels (app controls verbosity: off/error/info/debug/trace)
- Q: When the event queue reaches capacity (high event rate exceeds processing speed), what should happen? → A: Unbounded queue (may exhaust memory under sustained load)
- Q: What minimum test coverage percentage is required to consider this milestone complete? → A: No specific percentage (functional acceptance only) - unit test all discrete, logic-only components thoroughly; platform-dependent code tested manually
- Q: Beyond clipboard operations (which are explicitly thread-safe per FR-053), what is the general thread safety model for the framework's APIs? → A: @MainActor (Swift concurrency model)
- Q: How should the framework communicate errors to application developers when operations fail (e.g., window creation fails, clipboard access denied, monitor enumeration error)? → A: Swift throwing functions with typed Error enum (recoverable errors); fatalError for programming mistakes
- Q: For runtime capability queries (FR-033, edge case line 112), what granularity should the framework provide for applications to check platform feature availability? → A: Capability groups (WindowCapabilities, ClipboardCapabilities, etc.) with per-feature boolean queries within each group; uniform naming conventions
- Q: Should Milestone 1 include support for Input Method Editors (IMEs) needed for international text input (Chinese, Japanese, Korean, Arabic, etc.)? → A: No - Latin-only for M1; IME deferred to future milestone

---

## User Scenarios & Testing

### Primary User Story
As an application developer, I need to build cross-platform windowing applications that work identically on Linux (X11 and Wayland), macOS, and Windows, with robust window management, input handling, and system integration capabilities. The application must handle high-DPI displays correctly, provide reliable redraw mechanisms, and integrate with system features like clipboards and multi-monitor setups.

### Acceptance Scenarios

#### Wave A: Linux Platform Parity

1. **Given** the Lumina framework is available on a Linux system with X11, **When** a developer creates a window with title, size constraints, and resizable properties, **Then** the window displays correctly with all properties honored by the window manager

2. **Given** the Lumina framework is available on a Linux system with Wayland, **When** a developer creates the same windowing application, **Then** the window displays identically to the X11 version (within compositor limitations)

3. **Given** a window is displayed on a high-DPI Linux monitor (2.0x scale factor), **When** the window renders content, **Then** content appears sharp and scales correctly, and the application can query the current scale factor

4. **Given** a window is running on Linux, **When** the user moves the mouse, clicks buttons, scrolls, and types on the keyboard, **Then** the application receives all input events in the correct order with accurate modifiers and coordinates

5. **Given** a Linux application with multiple windows, **When** the user posts custom events from background threads, **Then** events are delivered to the correct windows in deterministic order

#### Wave B: macOS Robustness & System Integration

6. **Given** a macOS application requires precise frame rendering, **When** the application requests a redraw or the system determines rendering is needed, **Then** the application receives explicit RedrawRequested events with optional dirty region information

7. **Given** a macOS application running animations, **When** the application switches control flow modes (Wait, Poll, or WaitUntil), **Then** the event loop behaves according to the selected mode with appropriate power consumption and timing precision

8. **Given** a macOS window, **When** the developer toggles decorations, enables transparency, or sets always-on-top behavior, **Then** the window appearance updates immediately with platform-appropriate rendering

9. **Given** a macOS application, **When** the application reads or writes text to the clipboard, **Then** clipboard operations complete successfully and interoperate with native macOS applications, with thread-safe access

10. **Given** a macOS system with multiple monitors, **When** the application queries monitor information, **Then** it receives accurate geometry, work areas, and scale factors for all displays, and is notified when the configuration changes

### Edge Cases

#### Linux-Specific Edge Cases
- What happens when a Wayland compositor doesn't support required protocols (e.g., fractional scaling)?
  - System must detect missing capabilities and either gracefully degrade or provide clear error messages

- What happens when moving a window between monitors with different scale factors on X11?
  - System must emit scale change events and allow the application to re-render at the new scale factor

- What happens when different X11 window managers have varying EWMH compliance?
  - System must use lowest-common-denominator features and document known window manager quirks

- What happens when a user runs a Wayland application but Wayland display server is not available?
  - System must detect environment and either fall back to X11 or provide clear error about missing Wayland support

#### macOS-Specific Edge Cases
- What happens when rapid window resizing occurs during a live resize operation?
  - System must coalesce redraw events to prevent redundant rendering

- What happens when clipboard is accessed from a non-main thread?
  - System must marshal clipboard calls to the main thread or fail with clear thread safety error

- What happens when a window moves between standard and ProMotion (120Hz) displays?
  - System must adjust frame pacing for the new refresh rate

- What happens when system monitor configuration changes while application is running (monitor connected/disconnected)?
  - System must emit monitor configuration change events with updated monitor list

#### Cross-Platform Edge Cases
- What happens when the same application code runs on all three platforms?
  - Wave A features must behave identically (window creation, input, DPI) across macOS, Windows, and Linux

- What happens when a feature is available on one platform but not another?
  - System must provide runtime capability queries organized by category (WindowCapabilities, ClipboardCapabilities, MonitorCapabilities, etc.) with per-feature boolean checks so applications can adapt behavior

#### Resource Exhaustion Edge Cases
- What happens when event rate exceeds processing speed (e.g., 10,000 events/sec)?
  - System uses unbounded queue; events accumulate in memory until processed or memory exhaustion occurs
  - Application is responsible for monitoring event processing latency and adapting event generation rate

---

## Requirements

### Functional Requirements

#### Wave A: Linux Support (X11 + Wayland)

**Application Lifecycle**
- **FR-001**: System MUST support starting the event loop in blocking mode (run) that waits efficiently for events without high CPU usage
- **FR-002**: System MUST support non-blocking event loop mode (poll) that processes available events and returns immediately
- **FR-003**: System MUST allow posting custom user events from any thread to the event queue
- **FR-004**: System MUST deliver events in deterministic order with proper type discrimination and latency < 1ms from OS event generation to application callback
- **FR-004a**: System MUST use an unbounded event queue that grows with memory availability (no artificial capacity limits)

**Window Management**
- **FR-005**: System MUST allow creating windows with configurable initial properties (title, size, position, resizability)
- **FR-006**: System MUST support showing, hiding, and destroying windows
- **FR-007**: System MUST allow updating window title at runtime
- **FR-008**: System MUST enforce minimum and maximum size constraints through the window manager
- **FR-009**: System MUST track window visibility state and emit visibility change events
- **FR-010**: System MUST track window focus state and emit focus gained/lost events
- **FR-011**: System MUST support programmatic window move and resize operations
- **FR-012**: System MUST emit events when windows are moved or resized by user or window manager

**DPI and Scaling**
- **FR-013**: System MUST provide distinct types for logical pixels and physical pixels
- **FR-014**: System MUST allow querying the current scale factor for each window
- **FR-015**: System MUST emit events when DPI or scale factor changes (monitor move, settings change)
- **FR-016**: System MUST initialize windows with correct scale factor based on initial monitor placement

**Input Handling**
- **FR-017**: System MUST deliver pointer move events with accurate logical coordinates
- **FR-018**: System MUST emit window enter/leave events when cursor crosses window boundaries
- **FR-019**: System MUST deliver mouse button events (down/up) for left, right, middle, and additional buttons
- **FR-020**: System MUST deliver vertical and horizontal scroll events with appropriate units
- **FR-021**: System MUST support high-resolution scroll deltas for precision input devices (touchpads)
- **FR-022**: System MUST deliver keyboard key down/up events for physical key presses
- **FR-023**: System MUST track modifier key states (Shift, Control, Alt, Super/Meta)
- **FR-024**: System MUST deliver character input events for text entry with Latin layout support (IME support for international text input deferred to future milestone)
- **FR-025**: System MUST handle key repeat events following system repeat rate settings
- **FR-026**: System MUST only deliver keyboard events to windows with keyboard focus

**Cursor Management**
- **FR-027**: System MUST provide standard cursor shapes (arrow, hand, text beam, crosshair, resize variants)
- **FR-028**: System MUST allow setting cursor per window
- **FR-029**: System MUST support showing and hiding the cursor
- **FR-030**: System MUST integrate cursors with system theme on Linux desktop environments

**Platform Backend Support**
- **FR-031**: System MUST implement X11 backend with correct window manager hint handling
- **FR-032**: System MUST implement Wayland backend using core protocols (xdg-shell)
- **FR-033**: System MUST detect available platform capabilities and organize them by category (WindowCapabilities, ClipboardCapabilities, MonitorCapabilities, etc.) with per-feature boolean queries for runtime adaptation
- **FR-034**: System MUST provide clear error messages when required features or protocols are missing

#### Wave B: macOS Robustness & System Integration

**Redraw Contract**
- **FR-035**: System MUST emit RedrawRequested events when rendering is needed
- **FR-036**: System MUST provide API for applications to request redraws programmatically
- **FR-037**: System MUST coalesce rapid resize operations to avoid redundant redraws
- **FR-038**: System MUST support deterministic frame pacing for animations
- **FR-039**: System MUST provide dirty region hints when available from the operating system

**Control Flow Modes**
- **FR-040**: System MUST support Wait mode where event loop blocks until events arrive (low power, default)
- **FR-041**: System MUST support Poll mode where event loop returns immediately after processing available events
- **FR-042**: System MUST support WaitUntil mode where event loop blocks until events arrive or deadline expires
- **FR-043**: System MUST allow switching between control flow modes at runtime
- **FR-044**: System MUST provide timeout precision within operating system scheduler limits for WaitUntil mode

**Window Decorations & Styles**
- **FR-045**: System MUST allow toggling window decorations (title bar, borders) at runtime
- **FR-046**: System MUST support always-on-top window behavior (floating above other windows)
- **FR-047**: System MUST support window transparency with alpha channel backgrounds
- **FR-048**: System MUST render platform-appropriate shadows for decorated and undecorated windows
- **FR-049**: System MUST control macOS-specific title bar button positioning and visibility

**Clipboard Integration**
- **FR-050**: System MUST allow reading UTF-8 text content from clipboard
- **FR-051**: System MUST allow writing UTF-8 text content to clipboard
- **FR-052**: System MUST detect when clipboard contents change externally (ownership tracking)
- **FR-053**: System MUST provide thread-safe clipboard operations with appropriate synchronization
- **FR-054**: System MUST handle proper text format negotiation for clipboard operations

**Monitor Management**
- **FR-055**: System MUST identify the system's primary display
- **FR-056**: System MUST enumerate all connected monitors
- **FR-057**: System MUST provide physical position and dimensions for each monitor
- **FR-058**: System MUST provide usable work area excluding system UI (menu bars, docks, taskbars)
- **FR-059**: System MUST determine which monitor a window currently resides on
- **FR-060**: System MUST emit events when monitor configuration changes (connect/disconnect/rearrange)

### Non-Functional Requirements

**Performance**
- **NFR-001**: Event delivery latency MUST be < 1ms from OS event generation to application callback to support hard real-time applications (gaming, CAD)
- **NFR-002**: Event loop in Wait mode MUST consume < 0.1% CPU when idle

**Scalability**
- **NFR-003**: System MUST support unlimited concurrent windows per application instance, bounded only by available system memory
- **NFR-004**: Per-window resource overhead MUST be minimal to enable high window counts without degradation

**Observability**
- **NFR-005**: System MUST provide configurable logging levels (off, error, info, debug, trace) controllable by the application
- **NFR-006**: Logging MUST cover: events, state transitions, platform-specific calls, capability detection, and error conditions
- **NFR-007**: Log output MUST include high-resolution timestamps for performance analysis

**Concurrency & Thread Safety**
- **NFR-008**: All windowing and event APIs MUST be isolated to the main actor using Swift's @MainActor annotation to ensure thread safety through the Swift concurrency model

**Error Handling**
- **NFR-008a**: Recoverable errors (window creation failure, clipboard access denied, missing capabilities) MUST be communicated via Swift throwing functions with typed Error enums
- **NFR-008b**: Programming errors (invalid API usage, precondition violations) MUST trigger fatalError with descriptive messages

**Testing & Quality**
- **NFR-009**: All discrete, platform-independent logic components MUST have comprehensive unit test coverage
- **NFR-010**: Platform-dependent code MUST be validated through manual testing on target platforms (macOS, Ubuntu X11/Wayland, Fedora Wayland, Arch Linux)
- **NFR-011**: No specific line coverage percentage is mandated; functional acceptance criteria determine completeness

### Key Entities

- **Window**: Represents an application window with properties like title, size, position, visibility, focus state, decorations, and transparency. Belongs to a single application and resides on one monitor at a time.

- **Event**: Represents system or user actions (window events, input events, redraw requests, custom user events). Contains timestamp, window identifier, and event-specific data (coordinates, modifiers, etc.).

- **Monitor**: Represents a physical display device with geometry (position, dimensions), work area, scale factor, and primary/secondary designation. Can host multiple windows.

- **Scale Factor**: Represents the DPI scaling multiplier for rendering (1.0x, 1.5x, 2.0x, etc.). Associated with monitors and used to convert between logical and physical pixel coordinates.

- **Backend**: Represents the platform-specific implementation layer (X11, Wayland, macOS Cocoa, Windows Win32). Provides windowing, input, and system integration capabilities.

- **Clipboard**: Represents the system clipboard for text data exchange. Supports read/write operations and ownership tracking for interoperability with native applications.

---

## Review & Acceptance Checklist

### Content Quality
- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

### Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

---

## Execution Status

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [x] Entities identified
- [x] Review checklist passed

---
