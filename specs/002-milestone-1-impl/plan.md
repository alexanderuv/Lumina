# Implementation Plan: Milestone 1 - Linux Support & macOS Wave B

**Branch**: `002-milestone-1-impl` | **Date**: 2025-10-20 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/Users/alexander/dev/apple/Lumina/specs/002-milestone-1-impl/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from file system structure or context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → design.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code, or `AGENTS.md` for all other agents).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary

Milestone 1 extends Lumina's cross-platform windowing framework to Linux (X11 and Wayland backends) while enhancing macOS with Wave B robustness features. The implementation adds comprehensive Linux platform support with XCB-based X11 and wayland-client Wayland backends, both integrating with the existing protocol-based architecture from M0. macOS gains explicit redraw events, advanced control flow modes (Wait/Poll/WaitUntil), window decorations/transparency controls, clipboard operations, and monitor enumeration. All platforms maintain API consistency through the LuminaApp/LuminaWindow protocols while supporting runtime capability queries for platform-specific features.

## Technical Context
**Language/Version**: Swift 6.2+ (strict concurrency, borrowing ownership model)
**Primary Dependencies**:
- macOS: AppKit (NSApplication, NSWindow, NSScreen, NSPasteboard, CADisplayLink)
- Linux X11: libxcb, libxcb-keysyms, libxcb-xkb, libxcb-xinput, libxkbcommon, libxkbcommon-x11
- Linux Wayland: libwayland-client, libxkbcommon, libdecor (optional)
- Windows: Win32 API (existing M0 implementation, unchanged in M1)
**Storage**: N/A (windowing framework, no persistent storage)
**Testing**: Swift Testing framework (NO XCTest per constitution)
**Target Platform**: macOS 15+ (Sequoia), Windows 11+, Linux (X11 and Wayland)
**Project Type**: Single library project (cross-platform framework)
**Performance Goals**:
- Event latency < 1ms (hard real-time for gaming/CAD)
- Idle CPU < 0.1% in Wait mode
- 60 fps frame pacing (macOS CADisplayLink)
**Constraints**:
- @MainActor thread safety (Swift concurrency model)
- No broken states (all commits must compile and pass tests)
- Borrowing ownership model preferred over ARC
- Zero P0/P1 bugs at release
**Scale/Scope**:
- Unlimited concurrent windows per application (bounded by system memory)
- 40-50 implementation tasks
- 4 platform backends (macOS M0+M1, Windows M0, Linux X11 M1, Linux Wayland M1)

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. API Documentation
- [x] All new public APIs have complete documentation (descriptions, parameters, return values, examples)
  - ✅ Design doc includes API documentation template for all new methods
  - ✅ Examples provided for pumpEvents(), clipboard operations, monitor enumeration
- [x] No public symbols exposed without documentation
  - ✅ All protocol extensions, new types documented in design phase

### II. No Broken States
- [x] All commits will compile and pass tests
  - ✅ Incremental implementation planned with working states at each milestone
  - ✅ Conditional compilation (#if os(Linux)) isolates platform code
- [x] WIP features are feature-flagged or in separate branches
  - ✅ Feature branch: 002-milestone-1-impl (isolated from main)

### III. Swift 6.2+ Modern Idioms
- [x] Uses Swift 6.2+ features (strict concurrency, modern result builders, type-safe APIs)
  - ✅ @MainActor isolation throughout
  - ✅ Sendable value types for all events, geometry, capabilities
  - ✅ consuming func close() for resource cleanup
- [x] Avoids legacy patterns and unsafe constructs unless justified
  - ✅ Minimal unsafe required (C interop for XCB/Wayland - justified by platform requirement)

### IV. Cross-Platform Compatibility
- [x] Feature works across all supported platforms (macOS 15+, Windows 11+, Linux) OR is explicitly documented as platform-specific
  - ✅ Wave A features (Linux support) work across all platforms
  - ✅ Wave B features (macOS-first) explicitly documented as platform-specific with capability queries
  - ✅ WindowCapabilities/ClipboardCapabilities/MonitorCapabilities provide runtime detection
- [x] Platform abstractions are clean and testable
  - ✅ LuminaApp/LuminaWindow protocols maintain clean abstraction
  - ✅ Platform-specific implementations isolated in Platforms/ directory

### V. Test Coverage & Quality (Swift Testing Only)
- [x] Comprehensive tests included using Swift Testing framework (unit, integration, platform-specific)
  - ✅ Unit tests for geometry, events, capabilities, control flow
  - ✅ Platform-specific manual test checklists for X11, Wayland, macOS Wave B
- [x] NO XCTest usage
  - ✅ Design specifies Swift Testing only
- [x] Tests written for discrete, testable components (no arbitrary coverage percentage targets)
  - ✅ Focus on logic-only components (per NFR-010)
  - ✅ Platform tests done manually as per constitution
- [x] Tests are maintainable, deterministic, and cover edge cases
  - ✅ Test design includes edge cases (DPI scaling, mixed monitors, clipboard ownership)
- [x] Tests support async/await patterns
  - ✅ Swift Testing natively supports async/await

### VI. Borrowing Ownership Model
- [x] Uses borrowing ownership model (`borrowing`, `consuming`) where feasible
  - ✅ consuming func close() for window cleanup (M0 pattern maintained)
  - ✅ Value types (Event, Monitor, Capabilities) avoid ARC entirely
- [x] Minimizes ARC overhead in performance-critical paths
  - ✅ Zero-copy event translation (stack-allocated)
  - ✅ Event queue uses value types
- [x] Documents justification when ARC is required
  - ✅ UserEventQueue requires reference type for cross-thread sharing (documented)
- [x] Prefers value types and stack allocation where possible
  - ✅ All events, geometry types, capabilities are value types

## Project Structure

### Documentation (this feature)
```
specs/002-milestone-1-impl/
├── spec.md              # Feature specification (completed)
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (completed)
├── design.md            # Phase 1 output (completed)
└── tasks.md             # Phase 2 output (/tasks command - pending)
```

### Source Code (repository root)
```
Sources/Lumina/
├── Core/                           # Platform-independent (M0 + M1 extensions)
│   ├── LuminaApp.swift             # [EXTENDED] Add pumpEvents(mode:)
│   ├── LuminaWindow.swift          # [EXTENDED] Add Wave B methods
│   ├── Events.swift                # [EXTENDED] Add RedrawEvent, MonitorEvent
│   ├── Geometry.swift              # [UNCHANGED]
│   ├── Monitor.swift               # [EXTENDED] Full Monitor API
│   ├── Cursor.swift                # [UNCHANGED]
│   ├── Clipboard.swift             # [NEW]
│   ├── Capabilities.swift          # [NEW]
│   ├── ControlFlowMode.swift       # [NEW]
│   ├── Errors.swift                # [EXTENDED]
│   ├── WindowID.swift              # [UNCHANGED]
│   └── WindowRegistry.swift        # [UNCHANGED]
│
├── Platforms/
│   ├── macOS/                      # M0 existing + Wave B
│   │   ├── MacApplication.swift    # [EXTENDED]
│   │   ├── MacWindow.swift         # [EXTENDED]
│   │   ├── MacInput.swift          # [UNCHANGED]
│   │   ├── MacMonitor.swift        # [EXTENDED]
│   │   ├── MacClipboard.swift      # [NEW]
│   │   └── MacCapabilities.swift   # [NEW]
│   │
│   ├── Windows/                    # M0 (unchanged in M1)
│   │   └── [existing M0 files]
│   │
│   └── Linux/                      # [NEW]
│       ├── LinuxApplication.swift  # Backend selection
│       ├── X11/
│       │   ├── X11Application.swift
│       │   ├── X11Window.swift
│       │   ├── X11Input.swift
│       │   ├── X11Monitor.swift
│       │   ├── X11Clipboard.swift
│       │   ├── X11Atoms.swift
│       │   └── X11Capabilities.swift
│       │
│       └── Wayland/
│           ├── WaylandApplication.swift
│           ├── WaylandWindow.swift
│           ├── WaylandInput.swift
│           ├── WaylandMonitor.swift
│           ├── WaylandClipboard.swift
│           ├── WaylandProtocols.swift
│           └── WaylandCapabilities.swift
│
└── CInterop/                       # [NEW]
    ├── CXCBLinux/
    │   ├── module.modulemap
    │   └── shims.h
    └── CWaylandLinux/
        ├── module.modulemap
        └── shims.h

Tests/LuminaTests/
├── Core/                            # [EXTENDED] Pure logic tests only
│   ├── EventTests.swift             # [EXTENDED] RedrawEvent, MonitorEvent enum tests
│   ├── GeometryTests.swift          # [UNCHANGED]
│   ├── ErrorTests.swift             # [EXTENDED] New error enum cases
│   ├── ControlFlowTests.swift       # [NEW] Deadline expiration logic
│   ├── CapabilitiesTests.swift      # [NEW] Capability struct equality/hashing
│   └── MonitorStructTests.swift     # [NEW] Monitor value type tests (no system calls)
│
└── Manual/                          # [NEW] Platform-dependent manual testing
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

**Structure Decision**: Single library project with platform-specific implementations. The existing M0 structure (protocol-based abstraction with platform subdirectories) is maintained and extended. Linux support adds a new `Platforms/Linux/` directory with X11 and Wayland subdirectories, following the same pattern as macOS and Windows. C interop for Linux system libraries is isolated in `CInterop/` directory with modulemaps.

## Phase 0: Outline & Research

**Status**: ✅ Complete

### Research Completed

1. **M0 Architecture Analysis** (codebase exploration)
   - Protocol-based abstraction (LuminaApp, LuminaWindow)
   - Unified event system (Event enum with associated values)
   - DPI/scaling support (LogicalSize/PhysicalSize)
   - Existing macOS/Windows implementations

2. **Linux Windowing Systems**
   - X11 via XCB: Connection management, event handling, EWMH, XKB, XInput2, DPI detection
   - Wayland: Core protocols (xdg-shell), libdecor for decorations, capability detection
   - Backend selection strategy (environment-based)

3. **macOS Wave B Features**
   - Redraw contract: NSView + CADisplayLink hybrid
   - Control flow modes: NSRunLoop integration
   - Window decorations/transparency: NSWindow style masks
   - Clipboard: NSPasteboard API
   - Monitor enumeration: NSScreen API

4. **Cross-Platform Patterns**
   - Capability system design (WindowCapabilities, ClipboardCapabilities, MonitorCapabilities)
   - Error handling strategy (typed LuminaError enum)
   - Thread safety with @MainActor
   - Performance optimization (zero-copy events, atom caching)

5. **Dependencies & Build System**
   - X11: libxcb, libxcb-keysyms, libxcb-xkb, libxcb-xinput, libxkbcommon
   - Wayland: libwayland-client, libxkbcommon, libdecor
   - Swift Package Manager configuration with system library targets

**Output**: [research.md](./research.md) - 13 sections, comprehensive technical context

## Phase 1: Design Document

**Status**: ✅ Complete

### Design Artifacts Created

1. **Comprehensive design document** → [design.md](./design.md)
   - 14 sections covering all aspects of implementation
   - Architecture overview with 3-layer design (Public API, Platform Abstraction, Native APIs)
   - Module organization (59 files: 17 M0 existing, 42 M1 additions)
   - Type system design (Event extensions, ControlFlowMode, Monitor, Clipboard, Capabilities)
   - Protocol extensions (LuminaApp, LuminaWindow with Wave B methods)
   - Platform-specific implementations:
     - macOS Wave B (6 files extended/new)
     - Linux X11 (7 files new)
     - Linux Wayland (7 files new)
   - Thread safety with @MainActor enforcement
   - Error handling with extended LuminaError enum
   - Performance optimizations (zero-copy events, atom caching, inline conversions)
   - Testing architecture (unit tests + manual platform checklists)
   - Documentation requirements (API docs, compatibility matrix)
   - Dependencies & build system (Package.swift, modulemaps)

2. **Agent context updated**
   - Ran `.specify/scripts/bash/update-agent-context.sh claude`
   - Updated CLAUDE.md with M1 technical context

**Output**: [design.md](./design.md) - 14 sections, complete implementation blueprint

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from design.md module organization and implementation sections
- Group tasks by feature area for logical progression
- Each new/extended file → implementation task
- Each test category → testing task
- Follow dependency order: Core types → Platform implementations → Integration

**Ordering Strategy**:
1. **Core Type Extensions** (foundation layer)
   - Extend Event enum with RedrawEvent/MonitorEvent
   - Implement ControlFlowMode, Deadline
   - Implement Monitor struct, Capabilities structs
   - Implement Clipboard API
   - Extend LuminaError enum
   - Mark [P] for parallel execution (independent files)

2. **macOS Wave B** (enhance existing platform)
   - Extend MacApplication.pumpEvents()
   - Extend MacWindow with decoration methods
   - Implement MacClipboard, MacMonitor
   - Add redraw tracking, monitor notifications
   - Sequential order (builds on M0 foundation)

3. **Linux X11** (new platform backend)
   - C interop setup (CXCBLinux modulemap)
   - X11Atoms caching
   - X11Application event loop
   - X11Window, X11Input, X11Monitor
   - X11Clipboard, X11Capabilities
   - Sequential order (dependencies: atoms → app → window → input)

4. **Linux Wayland** (new platform backend)
   - C interop setup (CWaylandLinux modulemap)
   - WaylandProtocols detection
   - WaylandApplication event loop
   - WaylandWindow, WaylandInput, WaylandMonitor
   - WaylandClipboard, WaylandCapabilities
   - Can run in parallel with X11 tasks [P]

5. **Testing & Documentation**
   - Unit tests for core types
   - Platform-specific tests (macOS Wave B, X11, Wayland)
   - Manual test checklists
   - API documentation updates
   - Platform compatibility matrix
   - Example applications
   - Can be parallelized [P]

**Estimated Output**: 45-50 numbered, dependency-ordered tasks in tasks.md

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)  
**Phase 4**: Implementation (execute tasks.md following constitutional principles)  
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

**Status**: ✅ No violations - All constitutional requirements met

No complexity deviations required. The design:
- Maintains M0 architectural patterns (no added complexity)
- Uses established protocol-based abstraction for new platforms
- Extends existing types cleanly without breaking changes
- Follows Swift 6.2+ idioms consistently
- Requires only justified unsafe code (C interop for platform APIs)


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command) ✅ 2025-10-20
- [x] Phase 1: Design complete (/plan command) ✅ 2025-10-20
- [x] Phase 2: Task planning approach described (/plan command) ✅ 2025-10-20
- [ ] Phase 3: Tasks generated (/tasks command) - NEXT STEP
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS ✅
- [x] Post-Design Constitution Check: PASS ✅
- [x] All NEEDS CLARIFICATION resolved ✅ (spec had 9 clarifications from Session 2025-10-20)
- [x] Complexity deviations documented ✅ (none required)

**Artifacts Generated**:
- [x] research.md (13 sections, comprehensive technical research)
- [x] design.md (14 sections, complete implementation blueprint)
- [x] CLAUDE.md updated with M1 context
- [ ] tasks.md (pending /tasks command)

**Next Command**: `/tasks` - Generate implementation task list

---
*Based on Constitution v1.4.2 - See `.specify/memory/constitution.md`*
