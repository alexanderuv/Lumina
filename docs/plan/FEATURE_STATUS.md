# Lumina (Windowing Library) — Feature-First Strategy & Plan

## Feature Parity Matrix Scaffold

| Feature                                  | macOS | Windows | Linux/X11 | Linux/Wayland |
|------------------------------------------|-------|---------|-----------|---------------|
| **Wave A – Core Windowing & Input**      |       |         |           |               |
| Event loop (run/poll, user events)       | ❌    | ❌      | ❌        | ❌            |
| Window create/show/close                 | ❌    | ❌      | ❌        | ❌            |
| Resize/move/title/focus                  | ❌    | ❌      | ❌        | ❌            |
| DPI/Scaling events                       | ❌    | ❌      | ❌        | ❌            |
| Keyboard (basic)                         | ❌    | ❌      | ❌        | ❌            |
| Mouse input (move/buttons/wheel)         | ❌    | ❌      | ❌        | ❌            |
| System cursors                           | ❌    | ❌      | ❌        | ❌            |
| **Wave B – Redraw & Robustness**         |       |         |           |               |
| Redraw events & frame pacing             | ❌    | ❌      | ❌        | ❌            |
| Control flow (Wait/Poll)                 | ❌    | ❌      | ❌        | ❌            |
| Decorations & transparency               | ❌    | ❌      | ❌        | ❌            |
| Clipboard (text)                         | ❌    | ❌      | ❌        | ❌            |
| Monitor enumeration (basic)              | ❌    | ❌      | ❌        | ❌            |
| **Wave C – Advanced Input & IME**        |       |         |           |               |
| Advanced keyboard mapping                | ❌    | ❌      | ❌        | ❌            |
| IME composition                          | ❌    | ❌      | ❌        | ❌            |
| Pointer lock/confine                     | ❌    | ❌      | ❌        | ❌            |
| Raw mouse input                          | ❌    | ❌      | ❌        | ❌            |
| **Wave D – Fullscreen & Theming**        |       |         |           |               |
| Borderless fullscreen                    | ❌    | ❌      | ❌        | ❌            |
| Exclusive fullscreen                     | ❌    | ❌      | ❌        | ❌            |
| Theme change events                      | ❌    | ❌      | ❌        | ❌            |
| Window icons & badges                    | ❌    | ❌      | ❌        | ❌            |
| **Wave E – Clipboard & Drag/Drop**       |       |         |           |               |
| Clipboard (rich: HTML, PNG, file URIs)   | ❌    | ❌      | ❌        | ❌            |
| Drag & Drop receive                      | ❌    | ❌      | ❌        | ❌            |
| Drag & Drop source                       | ❌    | ❌      | ❌        | ❌            |
| **Wave F – Polish & Power Events**       |       |         |           |               |
| Power/session events                     | ❌    | ❌      | ❌        | ❌            |
| Decorationsless window movement          | ❌    | ❌      | ❌        | ❌            |
| Transparency/vibrancy                    | ❌    | ❌      | ❌        | ❌            |
| Notifications & badging hooks            | ❌    | ❌      | ❌        | ❌            |
