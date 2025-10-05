# Tasks: Milestone 0 - Wave A Core Windowing & Input

**Input**: Design documents from `specs/001-milestone-0-spec/`
**Prerequisites**: plan.md, research.md, design.md
**Methodology**: Implementation-first (NOT TDD) - tests verify behavior after implementation

## Execution Flow (main)
```
1. Load plan.md from feature directory
   → Extract: Swift 6.2+, AppKit/Win32, borrowing ownership model
   → Structure: Sources/{Lumina, LuminaPlatformMac, LuminaPlatformWin}
2. Load design documents:
   → design.md: Type system, platform backends, public API
   → research.md: Technical decisions (protocol-oriented, borrowing semantics)
3. Generate tasks by layer (implementation-first):
   → Setup: Package.swift, project structure
   → Foundation: Geometry, Events, Errors (parallel)
   → Platforms: macOS backend, Windows backend (parallel)
   → Public API: Application, Window, Cursor
   → Examples: HelloWindow, InputExplorer, ScalingDemo (parallel)
   → Tests: Unit tests (discrete components), platform-specific tests (after implementation)
4. Apply task rules:
   → Different files = mark [P] for parallel
   → Same file = sequential (no [P])
   → Implementation before tests (per constitution)
5. Number tasks sequentially (T001, T002...)
6. Validate constitutional compliance
7. Return: SUCCESS (tasks ready for execution)
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions
- All paths relative to repository root

## Path Conventions
- **Sources/Lumina/**: Public cross-platform API
- **Sources/LuminaPlatformMac/**: macOS backend (AppKit/Cocoa)
- **Sources/LuminaPlatformWin/**: Windows backend (Win32 API)
- **Tests/LuminaTests/**: Cross-platform unit tests
- **Tests/LuminaPlatformMacTests/**: macOS-specific tests
- **Tests/LuminaPlatformWinTests/**: Windows-specific tests
- **Examples/**: Example applications

---

## Phase 3.1: Project Setup

- [ ] **T001** Create Package.swift manifest with three targets: Lumina (public API), LuminaPlatformMac (macOS backend), LuminaPlatformWin (Windows backend)
  - **Files**: `Package.swift`
  - **Details**: Configure Swift 6.2+ language mode, strict concurrency, platform conditionals (#if os(macOS)/#if os(Windows))
  - **Dependencies**: None

- [ ] **T002** Create project directory structure per plan.md
  - **Files**: `Sources/Lumina/`, `Sources/LuminaPlatformMac/`, `Sources/LuminaPlatformWin/`, `Tests/LuminaTests/`, `Tests/LuminaPlatformMacTests/`, `Tests/LuminaPlatformWinTests/`, `Examples/`
  - **Details**: Create all source and test directories, ensure proper structure for Swift Package Manager
  - **Dependencies**: T001

- [ ] **T003** [P] Configure .gitignore for Swift project
  - **Files**: `.gitignore`
  - **Details**: Add .build/, .swiftpm/, Package.resolved, .DS_Store, Xcode-specific patterns
  - **Dependencies**: None

---

## Phase 3.2: Foundation Layer (Implementation)

**Layer 1: Core Value Types (Parallel - Independent Files)**

- [ ] **T004** [P] Implement Geometry types in Sources/Lumina/Geometry.swift
  - **Files**: `Sources/Lumina/Geometry.swift`
  - **Details**: Implement LogicalSize, PhysicalSize, LogicalPosition, PhysicalPosition structs with Sendable conformance, conversion methods (toPhysical/toLogical with scale factor), Hashable conformance
  - **Dependencies**: T002

- [ ] **T005** [P] Implement Event type hierarchy in Sources/Lumina/Events.swift
  - **Files**: `Sources/Lumina/Events.swift`
  - **Details**: Implement Event enum (window/pointer/keyboard/user), WindowEvent, PointerEvent, KeyboardEvent, MouseButton, KeyCode, ModifierKeys (OptionSet), UserEvent with Sendable conformance throughout
  - **Dependencies**: T002, T004 (needs LogicalPosition for pointer events)

- [ ] **T006** [P] Implement error types in Sources/Lumina/Errors.swift
  - **Files**: `Sources/Lumina/Errors.swift`
  - **Details**: Implement LuminaError enum with cases: windowCreationFailed(reason: String), platformError(code: Int, message: String), invalidState(String), eventLoopFailed(reason: String). Add Sendable conformance
  - **Dependencies**: T002

- [ ] **T007** [P] Implement WindowID type in Sources/Lumina/WindowID.swift
  - **Files**: `Sources/Lumina/WindowID.swift`
  - **Details**: Implement WindowID struct (Identifiable, Sendable, Hashable) using UUID or platform-specific handle wrapper
  - **Dependencies**: T002

---

## Phase 3.3: Platform Backends (Implementation)

**Layer 2a: macOS Backend (Sequential within platform)**

- [ ] **T008** Implement EventLoopBackend protocol in Sources/Lumina/EventLoopBackend.swift
  - **Files**: `Sources/Lumina/EventLoopBackend.swift`
  - **Details**: Define internal protocol with methods: run(), poll() -> Bool, wait(), postUserEvent(_:), quit(). Mark as Sendable. Document that this is internal API only
  - **Dependencies**: T005 (needs UserEvent), T006 (needs LuminaError)

- [ ] **T009** Implement WindowBackend protocol in Sources/Lumina/WindowBackend.swift
  - **Files**: `Sources/Lumina/WindowBackend.swift`
  - **Details**: Define internal protocol with id: WindowID, show(), hide(), close(), setTitle(_:), size(), resize(_:), position(), moveTo(_:), setMinSize(_:), setMaxSize(_:), requestFocus(), scaleFactor(). Use borrowing parameters where appropriate
  - **Dependencies**: T004 (needs geometry types), T006 (needs errors), T007 (needs WindowID)

- [ ] **T010** Implement MacApplication (EventLoopBackend) in Sources/LuminaPlatformMac/MacApplication.swift
  - **Files**: `Sources/LuminaPlatformMac/MacApplication.swift`
  - **Details**: Implement EventLoopBackend using NSApp.nextEvent for run/poll, CFRunLoop for wait mode, NSEvent → Lumina Event translation. Thread-safe user event queue. Mark @MainActor
  - **Dependencies**: T008, conditional compilation (#if os(macOS))

- [ ] **T011** Implement MacWindow (WindowBackend) in Sources/LuminaPlatformMac/MacWindow.swift
  - **Files**: `Sources/LuminaPlatformMac/MacWindow.swift`
  - **Details**: Implement WindowBackend wrapping NSWindow. Handle create() factory method returning Result<MacWindow, LuminaError>, coordinate conversion (AppKit bottom-left → top-left), backingScaleFactor for DPI
  - **Dependencies**: T009, T010

- [ ] **T012** Implement NSEvent translation helpers in Sources/LuminaPlatformMac/MacInput.swift
  - **Files**: `Sources/LuminaPlatformMac/MacInput.swift`
  - **Details**: Functions to translate NSEvent types to PointerEvent, KeyboardEvent, WindowEvent. Handle modifier key mapping, coordinate conversion
  - **Dependencies**: T005, T010

**Layer 2b: Windows Backend (Parallel to macOS - Sequential within platform)**

- [ ] **T013** [P] Implement WinApplication (EventLoopBackend) in Sources/LuminaPlatformWin/WinApplication.swift
  - **Files**: `Sources/LuminaPlatformWin/WinApplication.swift`
  - **Details**: Implement EventLoopBackend using GetMessage/PeekMessage/DispatchMessage, WaitMessage for low-power mode, COM initialization for DPI awareness (SetProcessDpiAwareness), WM_* message → Lumina Event translation
  - **Dependencies**: T008, conditional compilation (#if os(Windows))

- [ ] **T014** [P] Implement WinWindow (WindowBackend) in Sources/LuminaPlatformWin/WinWindow.swift
  - **Files**: `Sources/LuminaPlatformWin/WinWindow.swift`
  - **Details**: Implement WindowBackend wrapping HWND. CreateWindowEx, window styles (WS_OVERLAPPEDWINDOW vs WS_OVERLAPPED), GetDpiForWindow for scale factor (dpi/96.0)
  - **Dependencies**: T009, T013

- [ ] **T015** [P] Implement WM_* message translation helpers in Sources/LuminaPlatformWin/WinInput.swift
  - **Files**: `Sources/LuminaPlatformWin/WinInput.swift`
  - **Details**: Functions to translate WM_* messages to PointerEvent, KeyboardEvent, WindowEvent. Handle WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_KEYDOWN, etc. Virtual key code mapping
  - **Dependencies**: T005, T013

---

## Phase 3.4: Public API Layer (Implementation)

**Layer 3: Public API (Sequential - depends on backends)**

- [ ] **T016** Implement Application public API in Sources/Lumina/Application.swift
  - **Files**: `Sources/Lumina/Application.swift`
  - **Details**: Implement @MainActor public struct Application: ~Copyable. Backend selection via conditional compilation. Expose init(), run(), poll(), wait(), postUserEvent(_:), quit(). Complete inline documentation with examples
  - **Dependencies**: T008, T010, T013

- [ ] **T017** Implement Window public API in Sources/Lumina/Window.swift
  - **Files**: `Sources/Lumina/Window.swift`
  - **Details**: Implement @MainActor public struct Window: Identifiable, ~Copyable. Backend wrapper with create(title:size:resizable:) factory. All window operations with borrowing/consuming parameters. Complete inline documentation
  - **Dependencies**: T009, T011, T014

- [ ] **T018** Implement Cursor API in Sources/Lumina/Cursor.swift
  - **Files**: `Sources/Lumina/Cursor.swift`
  - **Details**: Implement @MainActor public struct Cursor with SystemCursor enum (arrow, ibeam, crosshair, hand, resize handles), static set(_:), hide(), show() methods. Platform-specific cursor mapping
  - **Dependencies**: T010, T013

---

## Phase 3.5: Example Applications (Implementation)

**Layer 4: Examples (Parallel - Independent executables)**

- [ ] **T019** [P] Create HelloWindow example in Examples/HelloWindow/
  - **Files**: `Examples/HelloWindow/Package.swift`, `Examples/HelloWindow/Sources/main.swift`
  - **Details**: Minimal example: create Application, create Window with title "Hello, Lumina!", show window, run event loop. Demonstrates basic window creation and event loop
  - **Dependencies**: T016, T017

- [ ] **T020** [P] Create InputExplorer example in Examples/InputExplorer/
  - **Files**: `Examples/InputExplorer/Package.swift`, `Examples/InputExplorer/Sources/main.swift`
  - **Details**: Display all pointer and keyboard events. **CRITICAL**: Dispatch events to async function to validate async/await works with event loop. Show event type, position, modifiers, etc.
  - **Dependencies**: T016, T017

- [ ] **T021** [P] Create ScalingDemo example in Examples/ScalingDemo/
  - **Files**: `Examples/ScalingDemo/Package.swift`, `Examples/ScalingDemo/Sources/main.swift`
  - **Details**: Demonstrate logical vs physical size conversion, display scale factor, handle scale factor change events when moving between monitors
  - **Dependencies**: T016, T017

---

## Phase 3.6: Comprehensive Testing (After Implementation)

**IMPORTANT: Tests verify implemented behavior - written AFTER implementation per constitution**

**Layer 5: Automated Unit Tests (Parallel - Pure logic only)**

- [ ] **T022** [P] Write geometry tests in Tests/LuminaTests/GeometryTests.swift
  - **Files**: `Tests/LuminaTests/GeometryTests.swift`
  - **Details**: Use Swift Testing framework (@Test, @Suite). Test LogicalSize/PhysicalSize conversion with various scale factors, edge cases (zero size, negative), Hashable conformance
  - **Dependencies**: T004, all implementations complete

- [ ] **T023** [P] Write event tests in Tests/LuminaTests/EventTests.swift
  - **Files**: `Tests/LuminaTests/EventTests.swift`
  - **Details**: Use Swift Testing framework. Test Event enum pattern matching, Sendable conformance, ModifierKeys OptionSet operations, KeyCode equality
  - **Dependencies**: T005, all implementations complete

- [ ] **T024** [P] Write error handling tests in Tests/LuminaTests/ErrorTests.swift
  - **Files**: `Tests/LuminaTests/ErrorTests.swift`
  - **Details**: Use Swift Testing framework. Test error creation, Error conformance, Sendable conformance
  - **Dependencies**: T006, all implementations complete

---

## Phase 3.7: Documentation & Polish

- [ ] **T025** Write API documentation in README.md
  - **Files**: `README.md`
  - **Details**: Getting started guide, installation instructions (Swift Package Manager), quick example, link to API reference, platform requirements (macOS 15+, Windows 11+)
  - **Dependencies**: All public API complete (T016-T018)

- [ ] **T026** Generate API reference documentation
  - **Files**: Documentation comments in all public API files
  - **Details**: Verify all public APIs have complete inline documentation (descriptions, parameters, return values, examples). Generate DocC documentation if applicable
  - **Dependencies**: All public API complete (T016-T018)

- [ ] **T027** [P] Write CONTRIBUTING.md
  - **Files**: `CONTRIBUTING.md`
  - **Details**: Reference constitution.md, explain implementation-first methodology (NOT TDD), Swift Testing only (no XCTest), borrowing ownership model guidelines, relative paths only
  - **Dependencies**: None

- [ ] **T028** Verify constitutional compliance checklist
  - **Files**: All source files
  - **Details**: Review all code for: (1) Complete API documentation, (2) Swift 6.2+ idioms (strict concurrency, borrowing/consuming), (3) Platform compatibility (macOS 15+, Windows 11+), (4) Swift Testing only (no XCTest), (5) Borrowing ownership in hot paths, (6) Relative paths only
  - **Dependencies**: All tasks complete

---

## Phase 3.8: Pre-Submission Verification

- [ ] **T029** Run automated test suite on macOS
  - **Command**: `swift test --parallel`
  - **Details**: Verify all automated tests pass on macOS 15+. No failures, no warnings
  - **Dependencies**: All tests written (T022-T024)

- [ ] **T030** Run automated test suite on Windows
  - **Command**: `swift test --parallel`
  - **Details**: Verify all automated tests pass on Windows 11+. No failures, no warnings
  - **Dependencies**: All tests written (T022-T024)

- [ ] **T031** Build all examples
  - **Command**: `swift build` in each Examples/ subdirectory
  - **Details**: Verify HelloWindow, InputExplorer, ScalingDemo all build without errors or warnings
  - **Dependencies**: All examples complete (T019-T021)

- [ ] **T032** Manual verification on macOS
  - **Details**: Execute each example app, verify window appears/closes, resize works, events work (keyboard/mouse), scaling demo shows correct DPI across monitors, InputExplorer dispatches keyboard events to async function (events printed to stdout, app remains responsive on repeated key presses), cursor changes work
  - **Dependencies**: T031

- [ ] **T033** Manual verification on Windows
  - **Details**: Execute each example app, verify window appears/closes, resize works, events work (keyboard/mouse), scaling demo shows correct DPI across monitors, InputExplorer dispatches keyboard events to async function (events printed to stdout, app remains responsive on repeated key presses), cursor changes work
  - **Dependencies**: T031

- [ ] **T034** Verify performance requirements
  - **Details**: Measure window creation time (<100ms)
  - **Dependencies**: All implementation complete

- [ ] **T035** Run documentation build
  - **Command**: `swift package generate-documentation` (if using DocC)
  - **Details**: Verify documentation builds without errors
  - **Dependencies**: T026

- [ ] **T036** Final code review against constitution
  - **Details**: Review against all 6 constitutional principles. Verify: (1) All public APIs documented, (2) No broken states, (3) Swift 6.2+ idioms used, (4) Platform abstractions clean, (5) Swift Testing only, (6) Borrowing ownership model applied
  - **Dependencies**: All tasks complete

---

## Summary Statistics

- **Total Tasks**: 36
- **Parallel Tasks**: 16 (marked with [P])
- **Sequential Tasks**: 20
- **Phases**: 8 (Setup, Foundation, Platforms, Public API, Examples, Testing, Docs, Verification)

## Dependency Graph

```
Setup (T001-T003)
  ├─→ Foundation Layer [P] (T004-T007)
  │     ├─→ Backend Protocols (T008-T009)
  │     │     ├─→ macOS Backend (T010-T012)
  │     │     └─→ Windows Backend [P] (T013-T015)
  │     │           └─→ Public API (T016-T018)
  │     │                 ├─→ Examples [P] (T019-T021)
  │     │                 └─→ Tests [P] (T022-T024)
  │     │                       └─→ Docs (T025-T027)
  │     │                             └─→ Compliance (T028)
  │     │                                   └─→ Verification (T029-T036)
```

## Parallel Execution Examples

**Foundation types (can run in parallel):**
```bash
# All independent files - safe to parallelize
swift build --target Lumina &  # T004, T005, T006, T007
```

**Platform backends (macOS and Windows in parallel):**
```bash
# macOS backend (T010-T012) and Windows backend (T013-T015) are independent
# Can develop both simultaneously on different machines or branches
```

**Example applications (all parallel):**
```bash
cd Examples/HelloWindow && swift build &
cd Examples/InputExplorer && swift build &
cd Examples/ScalingDemo && swift build &
wait
```

**Unit tests (all parallel):**
```bash
swift test --parallel  # Automatically parallelizes T022-T024
```

## Constitutional Compliance Notes

✅ **Implementation-First Methodology**: Tasks follow Implement → Verify → Test workflow (NOT TDD)

✅ **Swift Testing Only**: All test tasks use Swift Testing framework, no XCTest references

✅ **Borrowing Ownership**: Event dispatch tasks (T010, T013) emphasize borrowing semantics

✅ **Platform Requirements**: macOS 15+, Windows 11+ specified in documentation tasks

✅ **Relative Paths**: All task descriptions use relative paths from repository root

✅ **No Arbitrary Coverage**: No coverage percentage mandates - focus on discrete, testable components

---

**Status**: Ready for implementation via `/implement` command or manual task execution
