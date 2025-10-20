# CXCBLinux Module

This module provides Swift bindings to the XCB (X protocol C-Binding) libraries for Linux X11 support.

## Required System Packages

### Ubuntu/Debian (apt)
```bash
sudo apt install \
    libxcb1-dev \
    libxcb-keysyms1-dev \
    libxcb-xkb-dev \
    libxcb-xinput-dev \
    libxcb-randr0-dev \
    libxkbcommon-dev \
    libxkbcommon-x11-dev
```

### Fedora/RHEL (dnf)
```bash
sudo dnf install \
    libxcb-devel \
    xcb-util-keysyms-devel \
    libxkbcommon-devel \
    libxkbcommon-x11-devel
```

### Arch Linux (pacman)
```bash
sudo pacman -S \
    libxcb \
    xcb-util-keysyms \
    libxkbcommon \
    libxkbcommon-x11
```

## What's Included

- **xcb**: Core X11 protocol C bindings
- **xcb-keysyms**: Keyboard symbol utilities
- **xcb-xkb**: X Keyboard Extension (XKB) support
- **xcb-xinput**: XInput2 extension for advanced input
- **xcb-randr**: XRandR extension for monitor enumeration
- **xkbcommon**: Modern XKB keymap interpretation
- **xkbcommon-x11**: XKB integration with X11

## Usage

Import this module from Swift code:

```swift
#if os(Linux)
import CXCBLinux

// Use XCB functions directly
let connection = xcb_connect(nil, nil)
// ...
#endif
```

## Architecture

The module provides:
1. Direct C API bindings via header includes
2. Helper shims for Swift-friendly API access
3. Link directives for all required libraries

Helper functions in `shims.h` provide simplified access to:
- Connection error checking
- File descriptor access for event loop integration
- Event type extraction and error detection
- Setup/screen iteration helpers
