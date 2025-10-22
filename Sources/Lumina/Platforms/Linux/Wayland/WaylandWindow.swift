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
        debugPrint("!!!!! [WaylandWindow.create] ENTRY - Function called !!!!!")
        // 1. Create Wayland surface
        guard let surface = wl_compositor_create_surface(compositor) else {
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create wl_surface"
            )
        }

        // 2. Create EGL window for GPU-accelerated rendering
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
        debugPrint("!!!!! [WaylandWindow.create] Created EGL window: \(eglWindow)")

        // 3. Set opaque region - tells compositor the surface is fully opaque
        let region = wl_compositor_create_region(compositor)
        if let region = region {
            wl_region_add(region, 0, 0, Int32(size.width), Int32(size.height))
            wl_surface_set_opaque_region(surface, region)
            wl_region_destroy(region)
        }

        // 4. Generate window ID (libdecor frame will be created later in show())
        let windowID = WindowID()

        // 5. Register surface with input system for event routing
        if let inputState = inputState {
            inputState.registerSurface(surface, windowID: windowID)
            debugPrint("!!!!! [WaylandWindow.create] Surface registered with input system !!!!!")
        }

        // 6. Create and return WaylandWindow (frame creation deferred to show())
        debugPrint("!!!!! [WaylandWindow.create] About to create struct !!!!!")
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
        debugPrint("!!!!! [WaylandWindow.create] Struct created, returning !!!!!")
        return window
    }

    // MARK: - LuminaWindow Protocol Implementation

    public mutating func show() {
        print("[SHOW] WaylandWindow.show() called!")

        // Create libdecor frame on first show
        if frame == nil {
            print("[SHOW] Creating libdecor frame")

            // Detach any buffers and commit before creating frame
            wl_surface_attach(surface, nil, 0, 0)
            wl_surface_commit(surface)

            // Create user data for callbacks
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
            print("[SHOW] User data allocated (configured = false)")

            // Use shared frame interface from application
            // All windows share the same interface; window identification via userData
            print("[SHOW] Using shared frame interface from application")

            // Wait for libdecor to be ready before decorating
            // This ensures libdecor has finished receiving all globals
            print("[SHOW] About to check application context...")
            print("[SHOW] Application is: \(String(describing: application))")
            if let appContext = application as? WaylandApplicationContext {
                print("[SHOW] Successfully cast to WaylandApplicationContext")
                print("[SHOW] Checking libdecorReady: \(appContext.state.libdecorReady)")
                print("[SHOW] Waiting for libdecor to be ready...")
                while !appContext.state.libdecorReady {
                    // Dispatch Wayland events (this will trigger the sync callback)
                    _ = wl_display_dispatch(display)
                    _ = libdecor_dispatch(decorContext, 0)
                }
                print("[SHOW] libdecor is ready!")
            } else {
                print("[SHOW] WARNING: Could not access application context, skipping ready wait")
            }

            print("[SHOW] About to call libdecor_decorate()")

            // Create libdecor frame using shared interface
            let frame = libdecor_decorate(
                decorContext,
                surface,
                frameInterface,  // Shared interface from application
                userDataPtr      // Window-specific userData for callbacks
            )
            print("[SHOW] libdecor_decorate() returned: \(String(describing: frame))")

            guard let frame = frame else {
                userDataPtr.deallocate()
                // Note: Do NOT free frameInterface - it's shared and owned by application
                print("[SHOW] ERROR: Failed to create libdecor frame")
                return
            }
            self.frame = frame
            print("[SHOW] Frame assigned successfully")

            // Set window properties BEFORE mapping
            libdecor_frame_set_title(frame, title)
            libdecor_frame_set_app_id(frame, "com.lumina.app")

            // Set capabilities before mapping
            let capabilities = LIBDECOR_ACTION_MOVE.rawValue |
                              LIBDECOR_ACTION_RESIZE.rawValue |
                              LIBDECOR_ACTION_CLOSE.rawValue
            libdecor_frame_set_capabilities(frame, libdecor_capabilities(rawValue: capabilities))

            // Set size constraints if not resizable
            if !resizable {
                libdecor_frame_set_min_content_size(frame, Int32(currentSize.width), Int32(currentSize.height))
                libdecor_frame_set_max_content_size(frame, Int32(currentSize.width), Int32(currentSize.height))
            }

            // Map frame to make window visible
            libdecor_frame_map(frame)
            print("[SHOW] Mapped libdecor frame")

            // Wait for configure callback - compositor must send configure before window shows
            print("[SHOW] Waiting for configure callback...")
            while !userDataPtr.pointee.configured {
                // Dispatch libdecor events (this will trigger configure callback)
                let dispatchResult = libdecor_dispatch(decorContext, 0)
                if dispatchResult < 0 {
                    print("[SHOW] ERROR: libdecor_dispatch failed with code \(dispatchResult)")
                    userDataPtr.deallocate()
                    return
                }

                // Also dispatch Wayland events
                _ = wl_display_dispatch_pending(display)
            }
            print("[SHOW] Configure callback received! Window is now configured.")

            // CRITICAL: Dispatch libdecor one more time to trigger the commit callback
            // After libdecor_frame_commit() is called in configure, libdecor needs
            // another dispatch cycle to actually invoke our commit callback
            print("[SHOW] Dispatching libdecor to trigger commit callback...")
            _ = libdecor_dispatch(decorContext, 0)
            _ = wl_display_dispatch_pending(display)

            // Also flush to ensure commit is sent to compositor
            _ = wl_display_flush(display)

            print("[SHOW] Post-configure dispatch complete")
        }

        isVisible = true
        print("[SHOW] Window show() complete - configure callback will handle final setup")
    }

    public mutating func hide() {
        // Unmap surface (hides window)
        // Note: libdecor doesn't have an explicit unmap, so we destroy and recreate if needed
        // For now, we just mark as hidden
        isVisible = false
        // TODO: Implement proper hide/show cycle with frame recreation if needed
    }

    public consuming func close() {
        // Clean up resources in reverse order of creation
        if let eglWindow = eglWindow {
            wl_egl_window_destroy(eglWindow)
        }

        // Clean up libdecor frame if it was created
        if let frame = frame {
            libdecor_frame_unref(frame)
        }

        wl_surface_destroy(surface)

        // Free the C struct user data if allocated
        if let userDataPtr = userDataPtr {
            userDataPtr.deallocate()
        }

        // Note: frameInterface is NOT owned by this window - managed by WaylandApplication
        // Do not free it here
    }

    public mutating func setTitle(_ title: String) {
        guard let frame = frame else { return }
        libdecor_frame_set_title(frame, title)
        // Commit the change
        libdecor_frame_commit(frame, nil, nil)
    }

    public func size() -> LogicalSize {
        return currentSize
    }

    public mutating func resize(_ size: LogicalSize) {
        currentSize = size

        // Resize EGL window - compositor handles buffer allocation automatically
        if let eglWindow = eglWindow {
            wl_egl_window_resize(
                eglWindow,
                Int32(size.width),
                Int32(size.height),
                0,
                0
            )
            print("[RESIZE] EGL window resized to \(size.width)x\(size.height)")
        }
    }

    public func position() -> LogicalPosition {
        // Wayland doesn't provide window position queries (compositor decision)
        // Return (0, 0) as position is not accessible in Wayland
        return LogicalPosition(x: 0, y: 0)
    }

    public mutating func moveTo(_ position: LogicalPosition) {
        // Wayland doesn't allow clients to set window position (compositor decision)
        // This is a no-op on Wayland
        // NOTE: Could log a warning here
    }

    public mutating func setMinSize(_ size: LogicalSize?) {
        minSize = size
        guard let frame = frame else { return }
        if let size = size {
            libdecor_frame_set_min_content_size(
                frame,
                Int32(size.width),
                Int32(size.height)
            )
        } else {
            // Reset to default (typically 0x0)
            libdecor_frame_set_min_content_size(frame, 0, 0)
        }
        libdecor_frame_commit(frame, nil, nil)
    }

    public mutating func setMaxSize(_ size: LogicalSize?) {
        maxSize = size
        guard let frame = frame else { return }
        if let size = size {
            libdecor_frame_set_max_content_size(
                frame,
                Int32(size.width),
                Int32(size.height)
            )
        } else {
            // Reset to default (typically 0x0 = unlimited)
            libdecor_frame_set_max_content_size(frame, 0, 0)
        }
        libdecor_frame_commit(frame, nil, nil)
    }

    public mutating func requestFocus() {
        // On Wayland, focus is managed by the compositor
        // We can request activation, but compositor may ignore it
        // libdecor doesn't expose xdg_activation, so this is a no-op
        // NOTE: Future implementation could use xdg-activation protocol directly
    }

    public func scaleFactor() -> Float {
        // TODO: Implement proper scale factor detection
        // Should use wl_output scale or wp_fractional_scale_v1
        // For now, return 1.0 (standard DPI)
        return 1.0
    }

    public mutating func requestRedraw() {
        // With EGL rendering, redrawing is handled by the rendering context (OpenGL/Vulkan)
        // We just damage the surface to tell the compositor to refresh
        wl_surface_damage(surface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(surface)

        // TODO: Post redraw event to application event queue
    }

    public mutating func setDecorated(_ decorated: Bool) throws {
        // libdecor manages decorations automatically
        // We could expose libdecor_frame_set_visibility() but it's not standard
        // For now, throw unsupported
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Manual decoration toggle (libdecor manages automatically)"
        )
    }

    public mutating func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        // Wayland has no standard always-on-top protocol
        // Compositor-dependent feature
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Always-on-top (no standard protocol)"
        )
    }

    public mutating func setTransparent(_ transparent: Bool) throws {
        // Wayland supports transparency natively via ARGB8888 surfaces
        // Already enabled by default in our buffer creation
        // This is a no-op (could be used to switch between RGB888 and ARGB8888)
    }

    public func capabilities() -> WindowCapabilities {
        return WindowCapabilities(
            supportsTransparency: true,  // Native ARGB8888 support
            supportsAlwaysOnTop: false,  // No standard protocol
            supportsDecorationToggle: false,  // libdecor manages automatically
            supportsClientSideDecorations: true  // libdecor provides CSD when needed
        )
    }

    public func currentMonitor() throws -> Monitor {
        // TODO: Implement monitor detection via wl_output
        // For now, return primary monitor
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Monitor detection (not yet implemented)"
        )
    }

    public func cursor() -> any LuminaCursor {
        // TODO: Implement WaylandCursor using cursor-shape-v1 or wl_cursor
        fatalError("WaylandCursor not yet implemented")
    }
}

// NOTE: libdecor frame callbacks are now defined in WaylandApplication.swift
// to avoid duplicate symbol issues when passing them to lumina_alloc_frame_interface()

#endif // os(Linux)
