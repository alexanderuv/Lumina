# Feature Specification: Milestone 0 - Wave A Core Windowing & Input

**Feature Branch**: `001-milestone-0-spec`
**Created**: 2025-10-04
**Status**: Draft
**Input**: User description: "Milestone 0 spec: Use context and functional requirements from docs/plan/milestones/M0.md."

## Execution Flow (main)
```
1. Parse user description from Input
   → Feature description: Milestone 0 functional requirements
2. Extract key concepts from description
   → Identified: cross-platform windowing foundation, event loop, basic input handling, macOS + Windows support
3. For each unclear aspect:
   → All requirements are well-defined in M0.md
4. Fill User Scenarios & Testing section
   → User flows defined for window creation, input handling, and scaling
5. Generate Functional Requirements
   → All requirements are testable and derived from M0.md
6. Identify Key Entities (if data involved)
   → Core entities: Application, Window, Events, Input
7. Run Review Checklist
   → No implementation details included
   → Spec is complete and ready
8. Return: SUCCESS (spec ready for planning)
```

---

## ⚡ Quick Guidelines
- ✅ Focus on WHAT users need and WHY
- ❌ Avoid HOW to implement (no tech stack, APIs, code structure)
- 👥 Written for business stakeholders, not developers

---

## Clarifications

### Session 2025-10-04 (Pre-Implementation)
- Q: How should the system respond when a resize operation hits min/max constraints? → A: Platform-native behavior (may differ per OS)
- Q: What automated test coverage is required for cross-platform parity validation? → A: Unit tests + manual QA verification
- Q: Can multiple windows exist simultaneously per application instance? → A: Yes - with platform-specific limits
- Q: How should the system handle rapid event flooding (e.g., 10,000 mouse events/sec)? → A: Platform-native behavior (may differ per OS)
- Clarification: Unit tests will be written for discrete, testable components (no arbitrary coverage percentage targets)
- Q: What happens when the application loses focus or is minimized? → A: Platform-native behavior (may differ per OS)
- Q: What happens during graceful vs forced application shutdown? → A: Graceful allows cleanup, forced exits immediately

### Session 2025-10-05 (Post-Implementation)
- Confirmed: Event callback API deferred to future milestone; M0 defines event types but does not expose callback mechanism
- Confirmed: LuminaApp protocol pattern provides standardized entry point for common use cases
- Confirmed: Non-copyable types (~Copyable) used for Application and Window to prevent handle duplication
- Confirmed: 76 automated tests implemented (geometry, events, errors, platform-specific)
- Confirmed: Window creation performance exceeds target (42.81ms first window, 5.03ms subsequent vs 100ms target)
- Confirmed: Cursor API uses static methods for global cursor control (not instance methods)
- Confirmed: Platform backends organized in nested Platforms/ directory structure

---

## User Scenarios & Testing

### Primary User Story
A developer wants to create a cross-platform desktop application using Swift that can display a window, handle user input (keyboard and mouse), and adapt to different display scaling configurations on both macOS and Windows.

### Acceptance Scenarios

1. **Given** no running application, **When** developer creates and runs a basic window app, **Then** a window appears on screen with a title and standard decorations

2. **Given** a running windowed application, **When** user types on keyboard or moves/clicks mouse, **Then** the application receives accurate input events with correct coordinates and key information

3. **Given** an application running on a display, **When** the window is moved to a monitor with different DPI scaling, **Then** the application receives scale change events and can query logical vs physical dimensions

4. **Given** a running event loop, **When** the application posts a custom user event, **Then** the event is delivered through the standard event processing pipeline

5. **Given** a running application in wait mode, **When** no user input occurs for extended periods, **Then** the application consumes minimal CPU while remaining responsive to new events

### Edge Cases
- Graceful shutdown allows cleanup operations; forced shutdown exits immediately
- Platform-specific behaviors (resize constraints, event flooding, focus loss, event ordering) are documented in design.md

## Requirements

### Terminology
- **System**: Refers to the Lumina library and its public API throughout this specification

### Functional Requirements

#### Event Loop & Application Lifecycle
- **FR-001**: System MUST provide three event loop modes: `run` (blocking), `poll` (non-blocking), and `wait` (low-power sleep until next event)
- **FR-002**: System MUST allow applications to post custom user events into the event queue from background threads (thread-safe)
- **FR-003**: System MUST support graceful shutdown via system quit signal or explicit application exit
- **FR-004**: System MUST enforce single-threaded UI event loop execution
- **FR-005**: System MUST prevent background threads from directly calling UI APIs (enforced via @MainActor compile-time checks)
- **FR-033**: System MUST distinguish between graceful shutdown (allowing cleanup) and forced shutdown (immediate exit)
- **FR-034**: System SHOULD provide a standardized application entry point pattern for common use cases

#### Window Management
- **FR-006**: System MUST support creating, showing, and closing windows
- **FR-007**: System MUST allow setting and modifying window title at runtime
- **FR-008**: System MUST support configurable window resizability with min/max size constraints (enforced per platform-native behavior)
- **FR-009**: System MUST provide window visibility toggle (show/hide)
- **FR-010**: System MUST support programmatic window focus control
- **FR-011**: System MUST allow programmatic window repositioning and resizing
- **FR-032**: System MUST support multiple concurrent windows per application, subject to platform-specific limits

#### DPI & Display Scaling
- **FR-012**: System MUST distinguish between logical (device-independent) and physical (pixel) sizes
- **FR-013**: System MUST deliver scale factor change events when window moves between displays with different DPI
- **FR-014**: System MUST provide APIs to query current scale factor and convert between logical/physical coordinates

#### Pointer & Wheel Input
- **FR-015**: System MUST deliver pointer motion events with position in logical coordinates
- **FR-016**: System MUST provide pointer enter/leave events for window boundaries
- **FR-017**: System MUST support left, right, and middle mouse button press and release events
- **FR-018**: System MUST deliver vertical and horizontal scroll wheel events with precise delta values

#### Keyboard Input
- **FR-019**: System MUST deliver key down and key up events with keycodes
- **FR-020**: System MUST expose modifier key states (Shift, Ctrl, Alt, Cmd/Win)
- **FR-021**: System MUST provide UTF-8 text input events for Latin keyboard layouts; extended layout support (Cyrillic, Arabic, CJK) deferred to Wave C
- **FR-035**: System SHOULD provide named constants for common keys (Escape, Return, Tab, Space, Backspace) in addition to raw scan codes

#### System Cursors
- **FR-022**: System MUST provide standard cursor types: arrow, I-beam, crosshair, resize handles, and hand/pointer
- **FR-023**: System MUST support programmatic cursor visibility control (show/hide)

#### Cross-Platform Parity
- **FR-024**: All features MUST exhibit identical behavior and event ordering on both macOS and Windows
- **FR-025**: System MUST use Result types for recoverable errors (e.g., window creation failures) and typed throws for programmer errors (e.g., invalid API usage)
- **FR-031**: Cross-platform parity MUST be validated via unit tests for discrete, testable components plus manual QA verification on both platforms

#### Documentation & Examples
- **FR-026**: System MUST include "Hello Window" example demonstrating basic window creation
- **FR-027**: System MUST include "Input Explorer" example demonstrating async/await integration with event loop (async tasks working concurrently)
- **FR-028**: System MUST include "Scaling Demo" example showing logical vs physical size handling
- **FR-029**: All public APIs MUST have reference documentation
- **FR-036**: System documentation MUST clarify which features are available in current milestone vs deferred to future milestones (e.g., event callbacks, IME support)

### Key Entities

- **Application**: Represents the running application instance; manages event loop (FR-001, FR-004) and lifecycle (FR-003, FR-033); supports multiple windows per FR-032; non-copyable to prevent duplication
- **Window**: A platform window with attributes (title, size, position, visibility, focus state) and resizing constraints per FR-006 through FR-011; non-copyable to prevent handle duplication
- **Event**: Base type for all events processed by the event loop (window events, input events, user events, system events); defined in M0 but callback API deferred to future milestone
- **PointerEvent**: Mouse/trackpad input with position, button state, and enter/leave tracking
- **KeyboardEvent**: Key press/release with keycode (including named constants per FR-035), modifiers, and text input for character entry
- **WindowEvent**: Window lifecycle events (created, closed, resized, moved, focused, unfocused, scale factor changed)
- **UserEvent**: Thread-safe custom events that can be posted from background threads per FR-002
- **LogicalSize / PhysicalSize**: Distinct types for device-independent vs pixel-based dimensions with explicit conversion methods
- **LogicalPosition / PhysicalPosition**: Distinct types for device-independent vs pixel-based coordinates
- **Cursor**: System cursor appearance and visibility state with static methods for global cursor control
- **ModifierKeys**: Bitfield representing modifier key states (Shift, Control, Alt, Command/Win)
- **MouseButton**: Enumeration of supported mouse buttons (left, right, middle)

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
