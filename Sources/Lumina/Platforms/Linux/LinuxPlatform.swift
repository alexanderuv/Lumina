#if os(Linux)

/// Linux platform backend selection.
///
/// Linux supports multiple display server protocols (Wayland and X11).
/// This enum allows selecting which backend to use.
public enum LinuxBackend {
    /// Use Wayland protocol (requires LUMINA_WAYLAND build flag)
    case wayland

    /// Use X11 protocol
    case x11

    /// Automatic detection: try Wayland first if WAYLAND_DISPLAY is set, fall back to X11
    case auto
}

#endif // os(Linux)
