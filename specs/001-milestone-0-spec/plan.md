
# Implementation Plan: Milestone 0 - Wave A Core Windowing & Input

**Branch**: `001-milestone-0-spec` | **Date**: 2025-10-04 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-milestone-0-spec/spec.md`

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
Deliver a cross-platform desktop windowing foundation for macOS and Windows with complete feature parity. The milestone provides core primitives for window creation, event loop management, user input handling (keyboard, mouse, touch), DPI/scaling support, and system cursor control. This establishes the foundation for any Swift desktop application to create windows and process user interactions across platforms.

## Technical Context
**Language/Version**: Swift 6.2+ (strict concurrency, modern result builders, borrowing ownership model)
**Primary Dependencies**:
- macOS: AppKit/Cocoa (CFRunLoop bridge for event loop), Core Graphics (DPI/scaling)
- Windows: Win32 API (message pump, window management), COM for DPI awareness
**Storage**: N/A (no persistence in M0)
**Testing**: Swift Testing framework only (XCTest prohibited per constitution)
**Target Platform**: macOS 15+ and Windows 11+ (desktop only, no mobile)
**Project Type**: Single Swift Package Manager library with platform-specific backends
**Performance Goals**:
- Event dispatch latency < 2ms average
- Window creation < 100ms on reference hardware
- No UI thread blocking > 16ms (60fps requirement)
**Constraints**:
- Single-threaded UI event loop (enforced)
- Identical event ordering across platforms (deterministic behavior)
- No Objective-C bridges (Swift-native API only)
- Borrowing ownership model preferred over ARC
**Scale/Scope**: Foundation library (~5-10k LOC), 3 example apps, comprehensive API documentation

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### I. API Documentation
- [x] All new public APIs have complete documentation (descriptions, parameters, return values, examples)
  - FR-030 mandates reference documentation for all public APIs
  - 3 example applications required (HelloWindow, InputExplorer, ScalingDemo)
- [x] No public symbols exposed without documentation
  - Spec requires developer documentation + API reference + usage guide

### II. No Broken States
- [x] All commits will compile and pass tests
  - CI pipelines for macOS and Windows required
  - Implementation-first methodology with test verification
- [x] WIP features are feature-flagged or in separate branches
  - Feature branch: 001-milestone-0-spec

### III. Swift 6.2+ Modern Idioms
- [x] Uses Swift 6.2+ features (strict concurrency, modern result builders, type-safe APIs)
  - Technical Context specifies Swift 6.2+ with strict concurrency
  - M0 spec requires "Swift-native, Sendable where applicable"
- [x] Avoids legacy patterns and unsafe constructs unless justified
  - Explicit constraint: "no Objective-C bridges" (Swift-native API only)

### IV. Cross-Platform Compatibility
- [x] Feature works across all supported platforms (macOS 15+, Windows 11+) OR is explicitly documented as platform-specific
  - M0 explicitly scoped to macOS 15+ and Windows 11+
  - FR-024: Identical behavior and event ordering on both platforms
- [x] Platform abstractions are clean and testable
  - Deliverables include Lumina (unified API) + platform-specific backends

### V. Test Coverage & Quality (Swift Testing Only)
- [x] Comprehensive tests included using Swift Testing framework (unit, integration, platform-specific)
  - Unit tests for discrete, testable components
  - Integration tests with golden event traces for cross-platform parity validation
  - Platform-specific tests for macOS and Windows backends
  - Automation CI for both platforms
- [x] NO XCTest usage
  - Technical Context: "Swift Testing framework only (XCTest prohibited)"
- [x] Tests are maintainable, deterministic, and cover edge cases
  - Edge cases documented in spec (resize constraints, event flooding, focus loss)
  - Golden event traces for integration tests
  - No arbitrary coverage percentage targets (per constitution clarification)
- [x] Tests support async/await patterns
  - Swift 6.2+ with strict concurrency enabled

### VI. Borrowing Ownership Model
- [x] Uses borrowing ownership model (`borrowing`, `consuming`) where feasible
  - Technical Context: "Borrowing ownership model preferred over ARC"
  - Performance requirement: <16ms UI thread blocking (60fps)
- [x] Minimizes ARC overhead in performance-critical paths
  - Event dispatch latency <2ms requires low overhead
- [x] Documents justification when ARC is required
  - Will be addressed in design phase for callbacks/async closures
- [x] Prefers value types and stack allocation where possible
  - LogicalSize/PhysicalSize are distinct value types per spec

## Project Structure

### Documentation (this feature)
```
specs/[###-feature]/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── design.md            # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
Sources/
├── Lumina/                     # Public API - cross-platform abstractions
│   ├── Application.swift       # Event loop modes (run, poll, wait)
│   ├── Window.swift            # Window lifecycle & attributes
│   ├── Events.swift            # Event types (base, pointer, keyboard, scale)
│   ├── Input.swift             # Keyboard & pointer input handling
│   ├── Geometry.swift          # LogicalSize, PhysicalSize, scaling
│   └── Cursor.swift            # System cursor types
│
├── LuminaPlatformMac/          # macOS backend (AppKit/Cocoa)
│   ├── MacApplication.swift    # CFRunLoop integration
│   ├── MacWindow.swift         # NSWindow wrapper
│   ├── MacEventLoop.swift      # Event pump & dispatch
│   └── MacInput.swift          # NSEvent translation
│
└── LuminaPlatformWin/          # Windows backend (Win32 API)
    ├── WinApplication.swift    # Message pump integration
    ├── WinWindow.swift         # HWND wrapper
    ├── WinEventLoop.swift      # GetMessage/DispatchMessage
    └── WinInput.swift          # WM_* message translation

Tests/
├── LuminaTests/                # Cross-platform unit tests
│   ├── EventLoopTests.swift
│   ├── WindowTests.swift
│   └── GeometryTests.swift
│
├── LuminaPlatformMacTests/     # macOS-specific tests
└── LuminaPlatformWinTests/     # Windows-specific tests

Examples/
├── HelloWindow/                # Basic window creation
├── InputExplorer/              # Event display demo
└── ScalingDemo/                # DPI/scaling demonstration

Package.swift                   # Swift Package Manager manifest
```

**Structure Decision**: Single Swift Package Manager library with modular targets. Lumina provides the public cross-platform API, while platform-specific backends (LuminaPlatformMac, LuminaPlatformWin) implement the abstractions. This separation ensures clean platform abstraction boundaries and testability.

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:
   ```
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

## Phase 1: Design Document
*Prerequisites: research.md complete*

1. **Create comprehensive design document** → `design.md`:
   - Architecture overview (modules, components, layers)
   - Type system design (structs, enums, protocols, type relationships)
   - Key abstractions and their responsibilities
   - Platform-specific implementation strategy
   - Thread safety and concurrency model
   - Error handling approach
   - Performance considerations and trade-offs

2. **Update agent file incrementally** (O(1) operation):
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
     **IMPORTANT**: Execute it exactly as specified above. Do not add or remove any arguments.
   - If exists: Add only NEW tech from current plan
   - Preserve manual additions between markers
   - Update recent changes (keep last 3)
   - Keep under 150 lines for token efficiency
   - Output to repository root

**Output**: design.md, agent-specific file

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design doc (design.md)
- Follow implementation-first methodology (per constitution, NOT TDD)
- Each module/component → implementation task followed by test task
- Structure: Foundation types → Platform backends → Public API → Examples → Tests

**Ordering Strategy** (Implementation-first, NOT TDD):
1. **Foundation Layer** (parallel where independent):
   - Geometry types (LogicalSize, PhysicalSize, positions)
   - Event types (Event enum hierarchy, Sendable conformance)
   - Error types (LuminaError enum)

2. **Platform Backends** (sequential per platform, platforms can be parallel):
   - macOS: EventLoopBackend → WindowBackend → Event translation
   - Windows: EventLoopBackend → WindowBackend → Event translation

3. **Public API Layer** (depends on backends):
   - Application struct (wraps backend)
   - Window struct (wraps backend)
   - Cursor API

4. **Examples** (depends on public API):
   - HelloWindow (basic window creation)
   - InputExplorer (event display with async/await validation - events dispatched to async function)
   - ScalingDemo (DPI/scaling demonstration)

5. **Test Suite** (after implementation, per constitution):
   - Unit tests for geometry/events (LuminaTests)
   - Platform-specific tests (LuminaPlatformMacTests, LuminaPlatformWinTests)
   - Integration tests (golden event traces)

**Parallelization** (mark [P] for):
- Foundation types (independent files)
- macOS and Windows backends (separate platforms)
- Example applications (independent executables)

**Estimated Output**: 35-40 numbered, dependency-ordered tasks in tasks.md

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)  
**Phase 4**: Implementation (execute tasks.md following constitutional principles)  
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
  - Completed: 2025-10-04
  - Output: research.md (8 research areas, all decisions documented)
- [x] Phase 1: Design complete (/plan command)
  - Completed: 2025-10-04
  - Output: design.md (complete architecture + type system)
  - Output: CLAUDE.md (agent context updated)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
  - Completed: 2025-10-04
  - Approach: Implementation-first, 35-40 tasks, 5-layer structure
- [ ] Phase 3: Tasks generated (/tasks command)
  - Pending: Run /tasks to generate tasks.md
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
  - All 6 principles satisfied, no violations
- [x] Post-Design Constitution Check: PASS
  - Design confirms constitutional compliance
  - Borrowing ownership in event dispatch
  - Swift 6.2+ with strict concurrency
  - Swift Testing only (no XCTest)
- [x] All NEEDS CLARIFICATION resolved
  - Technical Context fully specified (no NEEDS CLARIFICATION markers)
  - Research phase resolved all unknowns
- [x] Complexity deviations documented
  - No deviations required (Complexity Tracking table empty)

**Execution Summary**:
- Template execution flow: Steps 1-9 completed successfully
- All required artifacts generated: plan.md, research.md, design.md, CLAUDE.md
- Ready for /tasks command (Phase 3)

---
*Based on Constitution v1.3.0 - See `.specify/memory/constitution.md`*
