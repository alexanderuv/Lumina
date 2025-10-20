/// Platform capability queries for runtime feature detection.
///
/// Lumina provides cross-platform windowing APIs, but not all features are available
/// on all platforms. Capability structs allow applications to query at runtime which
/// features are supported before attempting to use them.
///
/// Use capability queries to provide graceful degradation when features are unavailable,
/// or to show/hide UI elements based on platform capabilities.

/// Window-related capabilities.
///
/// WindowCapabilities describes which window features are supported on the current
/// platform. Query these capabilities before using optional window features like
/// transparency or always-on-top windows.
///
/// Example:
/// ```swift
/// let caps = window.capabilities()
/// if caps.supportsTransparency {
///     try window.setTransparent(true)
///     // Set transparent background
/// } else {
///     // Fall back to opaque background
/// }
/// ```
public struct WindowCapabilities: Sendable, Hashable {
    /// Whether the platform supports transparent windows with alpha channel.
    ///
    /// Transparent windows allow per-pixel alpha blending, enabling effects like
    /// rounded corners, drop shadows, or custom shaped windows.
    ///
    /// Platform support:
    /// - macOS: ✅ Supported (NSWindow isOpaque)
    /// - Windows: ✅ Supported (layered windows with WS_EX_LAYERED)
    /// - Linux X11: ⚠️ Partial (requires ARGB visual, not widely supported)
    /// - Linux Wayland: ✅ Supported (native ARGB8888 surfaces)
    public let supportsTransparency: Bool

    /// Whether the platform supports always-on-top windows.
    ///
    /// Always-on-top windows remain above other windows even when not focused.
    /// Useful for tool palettes, notifications, or floating toolbars.
    ///
    /// Platform support:
    /// - macOS: ✅ Supported (NSWindow.level = .floating)
    /// - Windows: ✅ Supported (HWND_TOPMOST)
    /// - Linux X11: ✅ Supported (_NET_WM_STATE_ABOVE)
    /// - Linux Wayland: ⚠️ Compositor-dependent (no standard protocol)
    public let supportsAlwaysOnTop: Bool

    /// Whether the platform supports toggling window decorations (title bar, borders).
    ///
    /// Decoration toggle allows creating borderless windows for custom chrome or
    /// fullscreen-like experiences while remaining in windowed mode.
    ///
    /// Platform support:
    /// - macOS: ✅ Supported (NSWindow styleMask)
    /// - Windows: ✅ Supported (WS_OVERLAPPEDWINDOW vs WS_POPUP)
    /// - Linux X11: ✅ Supported (_MOTIF_WM_HINTS)
    /// - Linux Wayland: ⚠️ Partial (xdg-decoration protocol, not universal)
    public let supportsDecorationToggle: Bool

    /// Whether the platform requires or supports client-side decorations.
    ///
    /// Client-side decorations (CSD) mean the application draws its own title bar
    /// and window borders. This is the default on Wayland but not on other platforms.
    ///
    /// Platform support:
    /// - macOS: ❌ Not applicable (system decorations only)
    /// - Windows: ❌ Not applicable (system decorations only)
    /// - Linux X11: ❌ Not applicable (window manager decorations)
    /// - Linux Wayland: ✅ Default behavior (CSD via libdecor or custom)
    public let supportsClientSideDecorations: Bool

    /// Create a WindowCapabilities struct.
    ///
    /// This initializer is typically called by platform implementations to advertise
    /// their supported features.
    ///
    /// - Parameters:
    ///   - supportsTransparency: Whether transparent windows are supported
    ///   - supportsAlwaysOnTop: Whether always-on-top windows are supported
    ///   - supportsDecorationToggle: Whether decoration toggling is supported
    ///   - supportsClientSideDecorations: Whether CSD is required/supported
    public init(
        supportsTransparency: Bool,
        supportsAlwaysOnTop: Bool,
        supportsDecorationToggle: Bool,
        supportsClientSideDecorations: Bool
    ) {
        self.supportsTransparency = supportsTransparency
        self.supportsAlwaysOnTop = supportsAlwaysOnTop
        self.supportsDecorationToggle = supportsDecorationToggle
        self.supportsClientSideDecorations = supportsClientSideDecorations
    }
}

/// Clipboard-related capabilities.
///
/// ClipboardCapabilities describes which clipboard data types are supported
/// on the current platform. Query these capabilities before attempting clipboard
/// operations with specific data types.
///
/// Example:
/// ```swift
/// let caps = Clipboard.capabilities()
/// if caps.supportsText {
///     try Clipboard.writeText("Hello, clipboard!")
/// }
/// if caps.supportsImages {
///     // Image clipboard support (future feature)
/// }
/// ```
public struct ClipboardCapabilities: Sendable, Hashable {
    /// Whether the platform supports text clipboard operations.
    ///
    /// Text clipboard support includes UTF-8 encoded plain text read and write.
    ///
    /// Platform support:
    /// - macOS: ✅ Supported (NSPasteboard)
    /// - Windows: ✅ Supported (CF_UNICODETEXT)
    /// - Linux X11: ✅ Supported (CLIPBOARD selection, UTF8_STRING)
    /// - Linux Wayland: ✅ Supported (wl_data_device, text/plain;charset=utf-8)
    public let supportsText: Bool

    /// Whether the platform supports image clipboard operations.
    ///
    /// Image clipboard support includes bitmap/PNG image read and write.
    /// This is a future feature not yet implemented.
    ///
    /// Platform support:
    /// - macOS: 🔮 Future (NSPasteboard with NSImage)
    /// - Windows: 🔮 Future (CF_DIB, CF_PNG)
    /// - Linux X11: 🔮 Future (image/png MIME type)
    /// - Linux Wayland: 🔮 Future (image/png MIME type)
    public let supportsImages: Bool

    /// Whether the platform supports HTML clipboard operations.
    ///
    /// HTML clipboard support includes rich text HTML read and write.
    /// This is a future feature not yet implemented.
    ///
    /// Platform support:
    /// - macOS: 🔮 Future (NSPasteboard with HTML)
    /// - Windows: 🔮 Future (CF_HTML)
    /// - Linux X11: 🔮 Future (text/html MIME type)
    /// - Linux Wayland: 🔮 Future (text/html MIME type)
    public let supportsHTML: Bool

    /// Create a ClipboardCapabilities struct.
    ///
    /// This initializer is typically called by platform implementations to advertise
    /// their supported clipboard data types.
    ///
    /// - Parameters:
    ///   - supportsText: Whether text clipboard operations are supported
    ///   - supportsImages: Whether image clipboard operations are supported
    ///   - supportsHTML: Whether HTML clipboard operations are supported
    public init(
        supportsText: Bool,
        supportsImages: Bool,
        supportsHTML: Bool
    ) {
        self.supportsText = supportsText
        self.supportsImages = supportsImages
        self.supportsHTML = supportsHTML
    }
}

/// Monitor-related capabilities.
///
/// MonitorCapabilities describes which monitor features are supported on the
/// current platform. Query these capabilities before relying on advanced monitor
/// features like fractional scaling or dynamic refresh rates.
///
/// Example:
/// ```swift
/// let caps = monitorCapabilities()
/// if caps.supportsFractionalScaling {
///     print("Platform supports fractional DPI scaling (1.25x, 1.5x, etc.)")
/// }
/// if caps.supportsDynamicRefreshRate {
///     print("Platform supports variable refresh rate (ProMotion, VRR)")
/// }
/// ```
public struct MonitorCapabilities: Sendable, Hashable {
    /// Whether the platform supports dynamic/variable refresh rates.
    ///
    /// Dynamic refresh rate allows the display to change its refresh rate on the fly
    /// for power savings or adaptive sync (e.g., Apple ProMotion, VRR displays).
    ///
    /// Platform support:
    /// - macOS: ✅ Supported (ProMotion on MacBook Pro 14"/16", Studio Display)
    /// - Windows: ⚠️ Partial (depends on GPU driver and display support)
    /// - Linux X11: ⚠️ Partial (depends on XRandR and driver support)
    /// - Linux Wayland: ⚠️ Partial (compositor-dependent)
    public let supportsDynamicRefreshRate: Bool

    /// Whether the platform supports fractional DPI scaling.
    ///
    /// Fractional scaling allows non-integer scale factors like 1.25x, 1.5x, 1.75x
    /// for better text readability on high-DPI displays.
    ///
    /// Platform support:
    /// - macOS: ✅ Supported (Retina scaling modes)
    /// - Windows: ✅ Supported (125%, 150%, 175%, etc.)
    /// - Linux X11: ⚠️ Partial (via Xft.dpi, application rendering)
    /// - Linux Wayland: ⚠️ Partial (wp_fractional_scale_v1 protocol, not universal)
    public let supportsFractionalScaling: Bool

    /// Create a MonitorCapabilities struct.
    ///
    /// This initializer is typically called by platform implementations to advertise
    /// their supported monitor features.
    ///
    /// - Parameters:
    ///   - supportsDynamicRefreshRate: Whether dynamic refresh rate is supported
    ///   - supportsFractionalScaling: Whether fractional DPI scaling is supported
    public init(
        supportsDynamicRefreshRate: Bool,
        supportsFractionalScaling: Bool
    ) {
        self.supportsDynamicRefreshRate = supportsDynamicRefreshRate
        self.supportsFractionalScaling = supportsFractionalScaling
    }
}
