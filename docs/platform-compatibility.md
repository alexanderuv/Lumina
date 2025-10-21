# Platform Compatibility Matrix

This document provides a comprehensive overview of Lumina's feature support across all platforms and backends.

## Feature Support Matrix

| Feature | macOS 15+ | Linux X11 | Linux Wayland | Notes |
|---------|-----------|-----------|---------------|-------|
| **Window Management** | | | | |
| Window creation | ✅ | ✅ | ✅ | All platforms |
| Window show/hide | ✅ | ✅ | ✅ | All platforms |
| Window close | ✅ | ✅ | ✅ | All platforms |
| Window title | ✅ | ✅ | ✅ | All platforms |
| Window resize | ✅ | ✅ | ✅ | All platforms |
| Window move | ✅ | ✅ | ✅ | All platforms |
| Size constraints (min/max) | ✅ | ⚠️ | ✅ | [1] |
| **Window Decorations** | | | | |
| Toggle decorations | ✅ | ✅ | ⚠️ | [2] |
| Always-on-top | ✅ | ✅ | ⚠️ | [3] |
| Transparency | ✅ | ❌ | ✅ | [4] |
| **Input Events** | | | | |
| Mouse movement | ✅ | ✅ | ✅ | All platforms |
| Mouse buttons | ✅ | ✅ | ✅ | All platforms |
| Mouse wheel | ✅ | ✅ | ✅ | All platforms |
| Keyboard input | ✅ | ✅ | ✅ | Latin scripts only (M1) |
| Modifiers (Shift, Ctrl, etc.) | ✅ | ✅ | ✅ | All platforms |
| Cursor shapes | ✅ | ✅ | ✅ | System cursors only (M1) |
| Cursor visibility | ✅ | ✅ | ✅ | All platforms |
| **DPI/Scaling** | | | | |
| HiDPI detection | ✅ | ⚠️ | ✅ | [5] |
| Integer scaling (2x, 3x) | ✅ | ✅ | ✅ | All platforms |
| Fractional scaling (1.5x) | ✅ | ⚠️ | ⚠️ | [6] |
| Mixed-DPI monitors | ✅ | ⚠️ | ✅ | [7] |
| **Monitor Support** | | | | |
| Monitor enumeration | ✅ | ✅ | ✅ | All platforms |
| Primary monitor detection | ✅ | ✅ | ✅ | All platforms |
| Monitor configuration changes | ✅ | ✅ | ✅ | All platforms |
| Work area (usable space) | ✅ | ✅ | ✅ | All platforms |
| **Clipboard** | | | | |
| Text read/write | ✅ | ✅ | ✅ | UTF-8 text only (M1) |
| Change detection | ✅ | ❌ | ❌ | macOS only (M1) |
| **Event Loop** | | | | |
| Wait mode (blocking) | ✅ | ✅ | ✅ | All platforms |
| Poll mode (non-blocking) | ✅ | ✅ | ✅ | All platforms |
| WaitUntil (timeout) | ✅ | ✅ | ✅ | All platforms |
| Redraw events | ✅ | ✅ | ✅ | macOS Wave B, Linux native |
| User events (thread-safe) | ✅ | ✅ | ✅ | All platforms |
| **Platform Features** | | | | |
| Client-side decorations (CSD) | N/A | N/A | ✅ | Wayland default |
| Server-side decorations (SSD) | ✅ | ✅ | ⚠️ | [8] |
| ProMotion (dynamic refresh) | ✅ | ❌ | ❌ | macOS only |

## Legend

- ✅ **Fully supported**: Feature works as expected on this platform
- ⚠️ **Partial support**: Feature works with limitations (see notes)
- ❌ **Not supported**: Feature not available on this platform
- N/A **Not applicable**: Feature doesn't apply to this platform

## Platform-Specific Notes

### [1] Size Constraints on X11

Window managers on X11 have varying levels of compliance with EWMH (Extended Window Manager Hints). Some tiling window managers (like i3) may ignore min/max size hints.

**Tested on:**
- ✅ GNOME (Mutter): Full support
- ✅ KDE Plasma (KWin): Full support
- ⚠️ i3: May ignore size hints
- ⚠️ Openbox: Partial support

### [2] Toggle Decorations on Wayland

Wayland decoration toggle requires the `xdg-decoration` protocol, which is compositor-dependent.

**Support by compositor:**
- ✅ KDE Plasma (KWin): Full support via xdg-decoration protocol
- ⚠️ GNOME (Mutter): Limited support (client-side decorations preferred)
- ❌ Sway: No support (always client-side decorations)
- ❌ Weston: No support

When xdg-decoration is not available, `setDecorated()` throws `unsupportedPlatformFeature`.

### [3] Always-on-Top on Wayland

Wayland has no standard protocol for window stacking order control. This is a compositor policy decision.

**Support by compositor:**
- ⚠️ KDE Plasma: May work via compositor-specific extensions
- ❌ GNOME: Not supported
- ❌ Sway: Not supported
- ❌ Weston: Not supported

`setAlwaysOnTop()` throws `unsupportedPlatformFeature` on Wayland in M1.

### [4] Transparency on X11

X11 transparency requires creating windows with ARGB visual, which is not implemented in M1. This feature is deferred to a future milestone.

### [5] HiDPI Detection on X11

X11 DPI detection uses a priority-based fallback system:

1. **XSETTINGS daemon** (Xft/DPI key) - Most reliable if available (GNOME, KDE, Xfce)
2. **Xft.dpi resource** from `~/.Xresources` - User-configured
3. **Physical dimensions** - Calculated from screen width_in_millimeters
4. **96 DPI fallback** - Default assumption (1.0x scale)

**Reliability:**
- ✅ GNOME X11: XSETTINGS reliable
- ✅ KDE X11: XSETTINGS reliable
- ⚠️ Minimal WMs (i3, Openbox): Relies on manual Xft.dpi configuration

### [6] Fractional Scaling

**macOS:** Native fractional scaling support (1.25x, 1.5x, 1.75x, etc.)

**Linux X11:** Fractional scaling via Xft.dpi is resolution-independent but may not reflect true fractional scaling on all WMs.

**Linux Wayland:** Fractional scaling requires `wp_fractional_scale_v1` protocol:
- ✅ GNOME 43+: Full support
- ✅ KDE Plasma 5.26+: Full support
- ⚠️ Sway: Partial support
- ❌ Weston: No support

Without `wp_fractional_scale_v1`, Wayland uses integer scale factors only.

### [7] Mixed-DPI on X11

X11 traditionally uses a single global DPI setting. Applications must manually handle per-monitor scaling when windows move between monitors. Lumina implements this in M1, but some WMs may not provide accurate per-monitor DPI information.

### [8] Server-Side Decorations on Wayland

Wayland defaults to client-side decorations (CSD). Server-side decorations (SSD) require compositor support via `xdg-decoration` protocol:

- ✅ KDE Plasma: Full SSD support
- ❌ GNOME: CSD preferred, limited SSD support
- ❌ Sway: CSD only
- ❌ Weston: CSD only

## Window Manager Compatibility

### X11 Window Managers

| WM | EWMH Support | Decorations | Always-on-Top | Size Constraints | Notes |
|----|--------------|-------------|---------------|------------------|-------|
| **Mutter** (GNOME) | Full | ✅ | ✅ | ✅ | Excellent compatibility |
| **KWin** (KDE) | Full | ✅ | ✅ | ✅ | Excellent compatibility |
| **i3** | Partial | ⚠️ | ⚠️ | ⚠️ | Tiling WM, ignores some hints |
| **Openbox** | Partial | ✅ | ✅ | ⚠️ | Good stacking WM support |
| **Xfce (Xfwm4)** | Full | ✅ | ✅ | ✅ | Good compatibility |

### Wayland Compositors

| Compositor | xdg-shell | xdg-decoration | fractional-scale | Notes |
|------------|-----------|----------------|------------------|-------|
| **Mutter** (GNOME) | v2+ | Limited | v1 (GNOME 43+) | CSD preferred |
| **KWin** (KDE Plasma) | v2+ | Full | v1 (5.26+) | Excellent support |
| **Sway** | v2+ | No | Partial | Tiling WM, CSD only |
| **Weston** | v2+ | No | No | Reference compositor |
| **Hyprland** | v2+ | No | Yes | Modern tiling compositor |

## Platform Requirements

### macOS

- **Minimum:** macOS 15 (Sequoia)
- **Architecture:** ARM64 (Apple Silicon) or x86_64 (Intel)
- **Frameworks:** AppKit, Foundation

### Linux (X11)

- **Libraries:**
  - libxcb (core protocol)
  - libxcb-keysyms (keyboard utilities)
  - libxcb-xkb (keyboard extension)
  - libxcb-xinput (XInput2 for advanced input)
  - libxcb-randr (monitor enumeration)
  - libxkbcommon (keymap interpretation)
  - libxkbcommon-x11 (X11 integration)

- **Install on Ubuntu/Debian:**
  ```bash
  sudo apt install libxcb1-dev libxcb-keysyms1-dev libxcb-xkb-dev \
                   libxcb-xinput-dev libxcb-randr0-dev \
                   libxkbcommon-dev libxkbcommon-x11-dev
  ```

- **Install on Fedora/RHEL:**
  ```bash
  sudo dnf install libxcb-devel xcb-util-keysyms-devel \
                   libxkbcommon-devel libxkbcommon-x11-devel
  ```

- **Install on Arch:**
  ```bash
  sudo pacman -S libxcb libxkbcommon
  ```

### Linux (Wayland)

- **Libraries:**
  - libwayland-client (core protocol)
  - libxkbcommon (keymap interpretation)

- **Optional:**
  - libdecor (for themed client-side decorations)

- **Install on Ubuntu/Debian:**
  ```bash
  sudo apt install libwayland-dev libxkbcommon-dev
  ```

- **Install on Fedora/RHEL:**
  ```bash
  sudo dnf install wayland-devel libxkbcommon-devel
  ```

- **Install on Arch:**
  ```bash
  sudo pacman -S wayland libxkbcommon
  ```

## Testing Matrix

Lumina has been tested on the following configurations:

### macOS

- ✅ macOS 15.0 (Sequoia) on Apple M1
- ✅ Standard displays (100 DPI, 1x scaling)
- ✅ Retina displays (220 DPI, 2x scaling)
- ✅ Mixed-DPI setups (1x + 2x monitors)

### Linux X11

- ✅ Ubuntu 24.04 LTS (GNOME X11)
- ✅ Fedora 40 (GNOME X11)
- ✅ Arch Linux (KDE X11)
- ✅ Debian 12 (Xfce)
- ⚠️ i3 on Arch (partial support - tiling WM quirks)

### Linux Wayland

- ✅ Ubuntu 24.04 LTS (GNOME Wayland)
- ✅ Fedora 40 (GNOME Wayland)
- ✅ Arch Linux (KDE Plasma Wayland)
- ⚠️ Sway on Arch (CSD only, no SSD)

## Known Issues and Limitations

### All Platforms (M1 Scope)

1. **Keyboard Input:** Latin scripts only (no IME support for CJK languages)
2. **Cursors:** System cursors only (no custom image cursors)
3. **Clipboard:** Text only (no images or HTML)
4. **Touch Input:** Not implemented
5. **Fullscreen Mode:** Not implemented

### X11 Specific

1. **Transparency:** Requires ARGB visual (not implemented in M1)
2. **Mixed-DPI:** Some window managers provide inaccurate per-monitor DPI
3. **Window Manager Quirks:** Tiling WMs (i3, awesome) may ignore size hints

### Wayland Specific

1. **Always-on-Top:** No standard protocol (compositor-dependent)
2. **Decoration Toggle:** Requires optional xdg-decoration protocol
3. **Fractional Scaling:** Requires optional wp_fractional_scale_v1 protocol
4. **Clipboard Change Detection:** Not supported (Wayland protocol limitation)

### macOS Specific

1. **Integer Scaling:** macOS only supports fractional scaling (1.25x, 1.5x, 2x) via Retina displays

## Future Enhancements

Planned for future milestones:

- **M2+:** Fullscreen mode, IME support, custom cursors, drag-and-drop
- **M3+:** Touch input, gamepad support, Vulkan/Metal integration
- **Platform Enhancements:** X11 transparency, Wayland protocol extensions

## Getting Help

If you encounter platform-specific issues:

1. Check this compatibility matrix for known limitations
2. Verify system dependencies are installed (see Platform Requirements above)
3. Test on a reference configuration (GNOME or KDE on Ubuntu/Fedora)
4. Report issues with your platform details: OS, version, WM/compositor, DPI settings

## References

- [X11 EWMH Specification](https://specifications.freedesktop.org/wm-spec/wm-spec-latest.html)
- [Wayland Protocol Documentation](https://wayland.freedesktop.org/docs/html/)
- [xdg-shell Protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml)
- [macOS NSWindow Documentation](https://developer.apple.com/documentation/appkit/nswindow)

---

**Last Updated:** 2025-10-20
**Lumina Version:** 0.2.0 (Milestone 1)
