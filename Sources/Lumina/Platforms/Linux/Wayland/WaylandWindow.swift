#if os(Linux) && LUMINA_WAYLAND
import CWaylandClient
import Foundation
import Glibc

/// Wayland implementation of LuminaWindow using libdecor.
///
/// Provides window management on Linux Wayland systems using libdecor for
/// automatic server-side/client-side decoration handling, providing compatibility
/// with all Wayland compositors (GNOME, KDE, Sway, Weston, etc.).
///
/// Architecture:
/// - Uses `libdecor_frame` for window management
/// - libdecor automatically selects SSD or CSD decorations
/// - Integrates with WaylandApplication's libdecor event loop
/// - Manages `wl_surface` for rendering content
///
/// Do not instantiate this type directly. Windows are created through
/// `LuminaApp.createWindow()`.
@MainActor
public struct WaylandWindow: LuminaWindow {
    /// Unique Lumina window ID
    public let id: WindowID

    /// libdecor frame (owns decoration logic) - created on show(), not create()
    /// Lazy creation avoids showing windows in taskbar before show()
    private var frame: OpaquePointer?

    private let surface: OpaquePointer
    private let compositor: OpaquePointer
    private let decorContext: OpaquePointer
    private let display: OpaquePointer
    private let shm: OpaquePointer

    /// EGL window for GPU-accelerated rendering
    /// Users can create OpenGL/Vulkan contexts on this later
    private var eglWindow: OpaquePointer?

    /// Current window size (logical coordinates)
    private var currentSize: LogicalSize

    /// Initial window title (stored until frame is created)
    private let title: String

    /// Whether window is resizable
    private let resizable: Bool

    /// Whether window is currently visible
    private var isVisible: Bool = false

    /// Minimum size constraint
    private var minSize: LogicalSize?

    /// Maximum size constraint
    private var maxSize: LogicalSize?

    /// Reference to application for event posting (weak to avoid retain cycles)
    /// Note: This is stored as an opaque pointer to avoid circular dependencies
    private weak var application: AnyObject?

    /// User data pointer for libdecor callbacks (C struct) - created on show()
    private var userDataPtr: UnsafeMutablePointer<LuminaWindowUserData>?

    /// Shared frame interface from application (one interface for all windows)
    /// NOT owned by this window - managed by WaylandApplication
    private let frameInterface: UnsafeMutablePointer<libdecor_frame_interface>

    private let inputState: WaylandInputState?

    /// Create a new Wayland window using libdecor.
    ///
    /// Internal method called by WaylandApplication.createWindow().
    ///
    /// - Parameters:
    ///   - decorContext: libdecor context from application
    ///   - frameInterface: Shared libdecor frame interface (one for all windows)
    ///   - display: wl_display from application
    ///   - compositor: wl_compositor for creating surfaces
    ///   - shm: wl_shm for buffer creation
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether window can be resized
    ///   - application: Reference to application for event posting
    ///   - inputState: Input state for surface registration
    /// - Returns: Newly created window
    /// - Throws: `LuminaError.windowCreationFailed` if creation fails
    static func create(
        decorContext: OpaquePointer,
        frameInterface: UnsafeMutablePointer<libdecor_frame_interface>,
        display: OpaquePointer,
        compositor: OpaquePointer,
        shm: OpaquePointer,
        title: String,
        size: LogicalSize,
        resizable: Bool,
        application: AnyObject?,
        inputState: WaylandInputState?
    ) throws -> WaylandWindow {
        guard let surface = wl_compositor_create_surface(compositor) else {
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create wl_surface"
            )
        }

        guard let eglWindow = wl_egl_window_create(
            surface,
            Int32(size.width),
            Int32(size.height)
        ) else {
            wl_surface_destroy(surface)
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create wl_egl_window"
            )
        }

        let region = wl_compositor_create_region(compositor)
        if let region = region {
            wl_region_add(region, 0, 0, Int32(size.width), Int32(size.height))
            wl_surface_set_opaque_region(surface, region)
            wl_region_destroy(region)
        }

        let windowID = WindowID()

        if let inputState = inputState {
            inputState.registerSurface(surface, windowID: windowID)
        }

        let window = WaylandWindow(
            id: windowID,
            frame: nil,
            surface: surface,
            compositor: compositor,
            decorContext: decorContext,
            display: display,
            shm: shm,
            eglWindow: eglWindow,
            currentSize: size,
            title: title,
            resizable: resizable,
            isVisible: false,
            minSize: resizable ? nil : size,
            maxSize: resizable ? nil : size,
            application: application,
            userDataPtr: nil,
            frameInterface: frameInterface,
            inputState: inputState
        )
        return window
    }

    // MARK: - LuminaWindow Protocol Implementation

    public mutating func show() {
        if frame == nil {
            wl_surface_attach(surface, nil, 0, 0)
            wl_surface_commit(surface)

            let userDataPtr = UnsafeMutablePointer<LuminaWindowUserData>.allocate(capacity: 1)
            withUnsafeBytes(of: id.id.uuid) { uuidBytes in
                let high = uuidBytes.load(fromByteOffset: 0, as: UInt64.self)
                let low = uuidBytes.load(fromByteOffset: 8, as: UInt64.self)
                userDataPtr.pointee = LuminaWindowUserData(
                    window_id_high: high,
                    window_id_low: low,
                    current_width: Float(currentSize.width),
                    current_height: Float(currentSize.height),
                    egl_window: eglWindow,
                    surface: surface,
                    shm: shm,
                    compositor: compositor,
                    configured: false
                )
            }
            self.userDataPtr = userDataPtr

            if let appContext = application as? WaylandApplicationContext {
                while !appContext.state.libdecorReady {
                    _ = wl_display_dispatch(display)
                    _ = libdecor_dispatch(decorContext, 0)
                }
            }

            // Create libdecor frame using shared interface
            let frame = libdecor_decorate(
                decorContext,
                surface,
                frameInterface,
                userDataPtr
            )

            guard let frame = frame else {
                userDataPtr.deallocate()
                return
            }
            self.frame = frame

            // Set window properties BEFORE mapping
            libdecor_frame_set_title(frame, title)
            libdecor_frame_set_app_id(frame, "com.lumina.app")

            let capabilities = LIBDECOR_ACTION_MOVE.rawValue |
                              LIBDECOR_ACTION_RESIZE.rawValue |
                              LIBDECOR_ACTION_CLOSE.rawValue
            libdecor_frame_set_capabilities(frame, libdecor_capabilities(rawValue: capabilities))

            if !resizable {
                libdecor_frame_set_min_content_size(frame, Int32(currentSize.width), Int32(currentSize.height))
                libdecor_frame_set_max_content_size(frame, Int32(currentSize.width), Int32(currentSize.height))
            }

            libdecor_frame_map(frame)

            while !userDataPtr.pointee.configured {
                let dispatchResult = libdecor_dispatch(decorContext, 0)
                if dispatchResult < 0 {
                    userDataPtr.deallocate()
                    return
                }
                _ = wl_display_dispatch_pending(display)
            }

            _ = libdecor_dispatch(decorContext, 0)
            _ = wl_display_dispatch_pending(display)
            _ = wl_display_flush(display)
        }

        isVisible = true
    }

    public mutating func hide() {
        isVisible = false
    }

    public consuming func close() {
        if let eglWindow = eglWindow {
            wl_egl_window_destroy(eglWindow)
        }

        if let frame = frame {
            libdecor_frame_unref(frame)
        }

        wl_surface_destroy(surface)

        if let userDataPtr = userDataPtr {
            userDataPtr.deallocate()
        }
    }

    public mutating func setTitle(_ title: String) {
        guard let frame = frame else { return }
        libdecor_frame_set_title(frame, title)
        libdecor_frame_commit(frame, nil, nil)
    }

    public func size() -> LogicalSize {
        return currentSize
    }

    public mutating func resize(_ size: LogicalSize) {
        currentSize = size

        if let eglWindow = eglWindow {
            wl_egl_window_resize(eglWindow, Int32(size.width), Int32(size.height), 0, 0)
        }
    }

    public func position() -> LogicalPosition {
        return LogicalPosition(x: 0, y: 0)
    }

    public mutating func moveTo(_ position: LogicalPosition) {
        // No-op on Wayland
    }

    public mutating func setMinSize(_ size: LogicalSize?) {
        minSize = size
        guard let frame = frame else { return }
        if let size = size {
            libdecor_frame_set_min_content_size(frame, Int32(size.width), Int32(size.height))
        } else {
            libdecor_frame_set_min_content_size(frame, 0, 0)
        }
        libdecor_frame_commit(frame, nil, nil)
    }

    public mutating func setMaxSize(_ size: LogicalSize?) {
        maxSize = size
        guard let frame = frame else { return }
        if let size = size {
            libdecor_frame_set_max_content_size(frame, Int32(size.width), Int32(size.height))
        } else {
            libdecor_frame_set_max_content_size(frame, 0, 0)
        }
        libdecor_frame_commit(frame, nil, nil)
    }

    public mutating func requestFocus() {
        // No-op: focus is managed by compositor
    }

    public func scaleFactor() -> Float {
        return 1.0
    }

    public mutating func requestRedraw() {
        wl_surface_damage(surface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(surface)
    }

    public mutating func setDecorated(_ decorated: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Manual decoration toggle (libdecor manages automatically)"
        )
    }

    public mutating func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Always-on-top (no standard protocol)"
        )
    }

    public mutating func setTransparent(_ transparent: Bool) throws {
        // No-op: ARGB8888 enabled by default
    }

    public func capabilities() -> WindowCapabilities {
        return WindowCapabilities(
            supportsTransparency: true,
            supportsAlwaysOnTop: false,
            supportsDecorationToggle: false,
            supportsClientSideDecorations: true
        )
    }

    public func currentMonitor() throws -> Monitor {
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Monitor detection (not yet implemented)"
        )
    }

    public func cursor() -> any LuminaCursor {
        fatalError("WaylandCursor not yet implemented")
    }
}

#endif // os(Linux)
