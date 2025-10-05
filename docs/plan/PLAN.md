Lumina (Windowing Library) — Feature-First Strategy & Plan

0) Scope & Principles
	•	Platforms (in order): macOS → Windows → Linux/X11 → Linux/Wayland.
	•	Goal: Practical parity with winit on desktop, but ship features in waves by usage frequency.
	•	Principles: Swift-native API surface, single-threaded UI invariants, deterministic behavior across platforms, minimal platform surprises, clear capability probing, robust docs and examples (no rendering dependency).

⸻

1) Feature Waves (priority order)

Wave A — Core Windowing & Input (highest impact)
	•	App & Event Loop Basics: run/poll modes, low-power wait, user events.
	•	Window Fundamentals: create/show/close, title, resizable, min/max size, visibility, focus, move/resize.
	•	DPI/Scaling: logical vs physical sizes, scale-factor change events.
	•	Pointer & Wheel Input: move, enter/leave, buttons, wheel/precision scroll.
	•	Keyboard Input (basic): key down/up, modifiers, text input for Latin layouts.
	•	System Cursors: default set, show/hide.
	•	Examples: “Hello Window,” “Input Explorer,” “Scaling Demo.”

Wave B — Robustness & Redraw Discipline
	•	Redraw Contract: explicit redraw events, coalesced resizes, frame pacing.
	•	Control Flow: Wait / Poll / WaitUntil modes with deadlines.
	•	Window Decorations & Styles: toggle decorations, always-on-top, transparency.
	•	Clipboard (Text): read/write UTF-8 text.
	•	Monitor Enumeration (basic): primary monitor, geometry, work area.

Wave C — Advanced Input & IME Foundations
	•	Keyboard (advanced): scancodes vs logical keys, auto-repeat, dead keys, layout-aware text.
	•	IME (phase 1): composition start/update/commit, preedit string, candidate window placement.
	•	Pointer Constraints: cursor lock/confine.
	•	Raw Pointer Input: high-resolution mouse deltas.

Wave D — Fullscreen, Multi-Monitor & Theming
	•	Fullscreen: borderless on target monitor; exclusive mode (Win/X11 first).
	•	Monitors (advanced): modes, scale, dynamic changes.
	•	Theme Events: light/dark preference.
	•	Window Icons & App Badges.

Wave E — Data Exchange (Clipboard++ & Drag/Drop)
	•	Clipboard (rich): HTML, images (PNG), file lists.
	•	Drag & Drop (receive): files/URIs, common MIME types.
	•	Drag & Drop (source): start drag with supplied data.

Wave F — Polish & Power Events
	•	Power & Session: sleep/wake, session lock/unlock.
	•	Decorationsless Window Movement.
	•	Transparency & Vibrancy.
	•	Notifications & Badging (hooks only).

⸻

2) Platform Sequencing by Feature Waves

Deliver each wave on macOS first, then Windows, then X11, then Wayland, before starting the next wave.

| Platform  | Wave A | Wave B | Wave C | Wave D | Wave E | Wave F |
|-----------|--------|--------|--------|--------|--------|--------|
| macOS     | ❌     | ❌     | ❌     | ❌     | ❌     | ❌     |
| Windows   | ❌     | ❌     | ❌     | ❌     | ❌     | ❌     |
| Linux/X11 | ❌     | ❌     | ❌     | ❌     | ❌     | ❌     |
| Wayland   | ❌     | ❌     | ❌     | ❌     | ❌     | ❌     |

⸻

1) Dependencies, Risks & Mitigations

High-risk Areas
	•	IME consistency: lock a cross-platform IME event model early.
	•	Wayland fragmentation: core protocols first, feature gate extensions.
	•	Fullscreen differences: prefer borderless fullscreen, expose capabilities.
	•	Clipboard/DnD MIME chaos: unify text/html/png/file URIs.

Medium-risk
	•	DPI/scaling mismatches: explicit logical vs physical types.
	•	Raw input on Wayland: feature gates and capability flags.

⸻

4) Capability Model & Parity Matrix
	•	Capabilities Query: apps can inspect runtime flags (e.g., supportsExclusiveFullscreen, supportsCursorLock).
	•	Parity Matrix: Rows = features (by wave); Columns = macOS / Windows / X11 / Wayland.
	•	Acceptance Gate: a wave is complete when no ❌ remains (except platform-limited cases).

⸻

5) Milestones & Deliverables

M0 — Wave A (Core) macOS & Windows
	•	Event loop, windows, DPI, input, cursors.
	•	Examples + docs.

M1 — Wave A (Linux) + Wave B (macOS)
	•	Add X11 + Wayland backends; decorations, clipboard, monitors.

M2 — Wave B (Windows/Linux) + Wave C (macOS)
	•	IME foundations, advanced keyboard, raw mouse.

M3 — Wave C (Windows/Linux)
	•	Full IME parity; IME conformance tests.

M4 — Wave D (All)
	•	Fullscreen, monitors, theme, icons.

M5 — Wave E (All)
	•	Clipboard rich data, drag/drop.

M6 — Wave F (All)
	•	Power/session events, transparency, custom chrome.

⸻

6) Testing, QA & Tooling
	•	Golden event traces per example.
	•	Input synthesis automation per OS.
	•	DPI multi-monitor tests.
	•	IME composition tests (EN/JP/ZH).
	•	Clipboard/DnD interop tests.
	•	CI: macOS + Windows hosted; Linux via Xvfb/Weston.

⸻

7) Documentation & Examples
	•	Wave A: Hello Window, Input Explorer, Scaling Demo.
	•	Wave B: Frame pacing, Clipboard Text.
	•	Wave C: IME Playground, Cursor Lock Sandbox.
	•	Wave D: Fullscreen Switcher, Theme Watcher.
	•	Wave E: Drag/Drop, Clipboard Rich Data.
	•	Wave F: Transparency Showcase, Sleep/Wake Logger.

⸻

8) Versioning & Stabilization
	•	0.y.z through Waves A–D.
	•	1.0 after Wave E stabilization.
	•	RFCs for breaking changes.

⸻

9) Out of Scope
	•	Mobile (iOS/Android).
	•	Gamepad/HID.
	•	Built-in rendering or widgets.
