# CWaylandClient - Wayland Protocol Bindings

This directory contains C bindings for Wayland protocols, generated from Wayland XML protocol specifications.

## Generated Files

The following files are generated from system Wayland protocol definitions:

**Headers** (`include/`):
- `xdg-shell-client-protocol.h` - XDG shell protocol (window management)
- `viewporter-client-protocol.h` - Viewport scaling protocol
- `pointer-constraints-unstable-v1-client-protocol.h` - Pointer locking/confinement
- `relative-pointer-unstable-v1-client-protocol.h` - Relative pointer motion
- `xdg-decoration-unstable-v1-client-protocol.h` - Server-side decorations

**Implementation** (`.`):
- `*-client-protocol.c` - Corresponding implementation files

## When to Regenerate

These files are checked into git and do **not** need to be regenerated for normal builds.

Regenerate only when:
- Updating to a newer Wayland protocol version
- Adding support for new protocols
- Fixing issues in the generation process

## How to Regenerate

```bash
swift package plugin generate-wayland-protocols
```

This will regenerate all protocol files from the system's Wayland protocol definitions (typically in `/usr/share/wayland-protocols`).

**Requirements:**
- `wayland-scanner` tool must be installed
- Wayland protocol XML files must be present

**Ubuntu/Debian:**
```bash
sudo apt install wayland-protocols
```

**Fedora:**
```bash
sudo dnf install wayland-devel wayland-protocols-devel
```

## Manual Files

- `module.modulemap` - Swift module map (hand-written)
- `shim.h` - C shim functions (hand-written)
