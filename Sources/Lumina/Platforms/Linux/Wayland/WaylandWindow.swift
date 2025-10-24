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
public final class WaylandWindow: LuminaWindow {
    /// Unique Lumina window ID
    public let id: WindowID

    /// libdecor frame (owns decoration logic) - created on show(), not create()
    /// Lazy creation avoids showing windows in taskbar before show()
    private nonisolated(unsafe) var frame: OpaquePointer?

    private nonisolated(unsafe) let surface: OpaquePointer
    private let compositor: OpaquePointer
    private let decorContext: OpaquePointer
    private let display: OpaquePointer
    private let shm: OpaquePointer

    /// EGL window for GPU-accelerated rendering
    /// Users can create OpenGL/Vulkan contexts on this later
    fileprivate nonisolated(unsafe) var eglWindow: OpaquePointer?

    /// Current window size (logical coordinates)
    fileprivate nonisolated(unsafe) var currentSize: LogicalSize

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

    /// User data pointer for libdecor callbacks (C struct) - created on show()
    private nonisolated(unsafe) var userDataPtr: UnsafeMutablePointer<LuminaWindowUserData>?

    /// Shared frame interface from application (one interface for all windows)
    /// NOT owned by this window - managed by WaylandApplication
    private let frameInterface: UnsafeMutablePointer<libdecor_frame_interface>

    fileprivate let inputState: WaylandInputState?

    /// Logger for window events
    fileprivate let logger: LuminaLogger

    // MARK: - Scale Tracking

    /// Output/scale pairs for surfaces this window occupies.
    /// When a surface enters an output, we track it here. When it leaves, we remove it.
    /// The current buffer scale is the maximum of all occupied outputs.
    fileprivate struct OutputScale {
        let output: OpaquePointer
        let scale: Int32
    }

    /// Outputs this surface currently occupies
    fileprivate nonisolated(unsafe) var outputScales: [OutputScale] = []

    /// Current buffer scale (maximum of all occupied outputs)
    fileprivate nonisolated(unsafe) var bufferScale: Int32 = 1

    /// Surface listener for enter/leave events (must persist)
    private nonisolated(unsafe) var surfaceListener: wl_surface_listener?

    /// Reference to monitor tracker for looking up scales
    fileprivate nonisolated(unsafe) weak var monitorTracker: WaylandMonitorTracker?

    /// Reference to application for cursor operations
    fileprivate weak var application: WaylandApplication?

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
    ///   - inputState: Input state for surface registration
    ///   - monitorTracker: Monitor tracker for scale lookups
    ///   - application: Reference to application for cursor operations
    /// - Returns: Newly created window
    /// - Throws: `LuminaError.windowCreationFailed` if creation fails
    init(
        decorContext: OpaquePointer,
        frameInterface: UnsafeMutablePointer<libdecor_frame_interface>,
        display: OpaquePointer,
        compositor: OpaquePointer,
        shm: OpaquePointer,
        title: String,
        size: LogicalSize,
        resizable: Bool,
        inputState: WaylandInputState?,
        monitorTracker: WaylandMonitorTracker?,
        application: WaylandApplication?
    ) throws {
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
        self.id = windowID
        self.frame = nil
        self.surface = surface
        self.compositor = compositor
        self.decorContext = decorContext
        self.display = display
        self.shm = shm
        self.eglWindow = eglWindow
        self.currentSize = size
        self.title = title
        self.resizable = resizable
        self.isVisible = false
        self.minSize = resizable ? nil : size
        self.maxSize = resizable ? nil : size
        self.userDataPtr = nil
        self.frameInterface = frameInterface
        self.inputState = inputState
        self.monitorTracker = monitorTracker
        self.application = application
        self.outputScales = []
        self.bufferScale = 1
        self.logger = LuminaLogger(label: "lumina.wayland.window", level: .info)

        if let inputState = inputState {
            inputState.registerSurface(surface, windowID: windowID)
        }

        // Set up wl_surface listener for enter/leave events
        setupSurfaceListener()
    }

    // MARK: - Libdecor Helpers

    private nonisolated var loader: LibdecorLoader { LibdecorLoader.shared }

    // MARK: - LuminaWindow Protocol Implementation

    public func show() {
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

            // Create libdecor frame using shared interface
            guard let decorateFunc = loader.libdecor_decorate else {
                userDataPtr.deallocate()
                return
            }

            let frame = decorateFunc(
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
            if let setTitle = loader.libdecor_frame_set_title {
                title.withCString { titlePtr in
                    setTitle(frame, titlePtr)
                }
            }

            if let setAppId = loader.libdecor_frame_set_app_id {
                // TODO: Make app ID configurable by the application
                "lumina.app".withCString { appIdPtr in
                    setAppId(frame, appIdPtr)
                }
            }

            // Set window capabilities (which controls are available)
            if let setCapabilities = loader.libdecor_frame_set_capabilities {
                let capabilities = LIBDECOR_ACTION_MOVE.rawValue |
                                  LIBDECOR_ACTION_RESIZE.rawValue |
                                  LIBDECOR_ACTION_CLOSE.rawValue
                setCapabilities(frame, capabilities)
            }

            if !resizable {
                if let setMinSize = loader.libdecor_frame_set_min_content_size {
                    setMinSize(frame, Int32(currentSize.width), Int32(currentSize.height))
                }
                if let setMaxSize = loader.libdecor_frame_set_max_content_size {
                    setMaxSize(frame, Int32(currentSize.width), Int32(currentSize.height))
                }
            }

            if let frameMap = loader.libdecor_frame_map {
                frameMap(frame)
            }

            if let dispatch = loader.libdecor_dispatch {
                while !userDataPtr.pointee.configured {
                    let dispatchResult = dispatch(decorContext, 0)
                    if dispatchResult < 0 {
                        userDataPtr.deallocate()
                        return
                    }
                    _ = wl_display_dispatch_pending(display)
                }

                _ = dispatch(decorContext, 0)
                _ = wl_display_dispatch_pending(display)
                _ = wl_display_flush(display)
            }
        }

        isVisible = true
    }

    public func hide() {
        isVisible = false
    }

    public func close() {
        cleanup()
    }

    deinit {
        cleanup()
    }

    private nonisolated func cleanup() {
        if let eglWindow = eglWindow {
            wl_egl_window_destroy(eglWindow)
            self.eglWindow = nil
        }

        if let frame = frame {
            if let frameUnref = loader.libdecor_frame_unref {
                frameUnref(frame)
            }
            self.frame = nil
        }

        wl_surface_destroy(surface)

        if let userDataPtr = userDataPtr {
            userDataPtr.deallocate()
            self.userDataPtr = nil
        }
    }

    public func setTitle(_ title: String) {
        guard let frame = frame else { return }
        if let setTitle = loader.libdecor_frame_set_title {
            title.withCString { titlePtr in
                setTitle(frame, titlePtr)
            }
        }
        if let commit = loader.libdecor_frame_commit {
            commit(frame, nil, nil)
        }
    }

    public func size() -> LogicalSize {
        // Read from user data (source of truth updated by configure callback)
        // Fall back to currentSize if frame not created yet
        if let userDataPtr = userDataPtr {
            return LogicalSize(
                width: Float(userDataPtr.pointee.current_width),
                height: Float(userDataPtr.pointee.current_height)
            )
        }
        return currentSize
    }

    public func resize(_ size: LogicalSize) {
        // Note: Programmatic resize doesn't really work on Wayland
        // The compositor controls window sizes via configure events
        // This method is kept for API compatibility but is largely a no-op
        currentSize = size

        if let eglWindow = eglWindow {
            wl_egl_window_resize(eglWindow, Int32(size.width), Int32(size.height), 0, 0)
        }
    }

    public func position() -> LogicalPosition {
        return LogicalPosition(x: 0, y: 0)
    }

    public func moveTo(_ position: LogicalPosition) {
        // No-op on Wayland
    }

    public func setMinSize(_ size: LogicalSize?) {
        minSize = size
        guard let frame = frame else { return }
        if let setMinSize = loader.libdecor_frame_set_min_content_size {
            if let size = size {
                setMinSize(frame, Int32(size.width), Int32(size.height))
            } else {
                setMinSize(frame, 0, 0)
            }
        }
        if let commit = loader.libdecor_frame_commit {
            commit(frame, nil, nil)
        }
    }

    public func setMaxSize(_ size: LogicalSize?) {
        maxSize = size
        guard let frame = frame else { return }
        if let setMaxSize = loader.libdecor_frame_set_max_content_size {
            if let size = size {
                setMaxSize(frame, Int32(size.width), Int32(size.height))
            } else {
                setMaxSize(frame, 0, 0)
            }
        }
        if let commit = loader.libdecor_frame_commit {
            commit(frame, nil, nil)
        }
    }

    public func requestFocus() {
        // No-op: focus is managed by compositor
    }

    public func scaleFactor() -> Float {
        return Float(bufferScale)
    }

    // MARK: - Scale Tracking Implementation

    /// Set up wl_surface listener to track enter/leave events.
    /// This allows us to track which outputs the surface occupies and calculate buffer scale.
    private func setupSurfaceListener() {
        surfaceListener = wl_surface_listener(
            enter: surfaceHandleEnter,
            leave: surfaceHandleLeave,
            preferred_buffer_scale: surfaceHandlePreferredBufferScale,
            preferred_buffer_transform: surfaceHandlePreferredBufferTransform
        )

        let windowPtr = Unmanaged.passUnretained(self).toOpaque()
        _ = withUnsafeMutablePointer(to: &surfaceListener!) { listenerPtr in
            wl_surface_add_listener(surface, listenerPtr, windowPtr)
        }
    }

    /// Update buffer scale from all occupied outputs.
    /// Finds the maximum scale across all outputs and applies it.
    nonisolated fileprivate func updateBufferScaleFromOutputs() {
        // Calculate maximum scale across all occupied outputs
        var maxScale: Int32 = 1
        for outputScale in outputScales {
            maxScale = max(maxScale, outputScale.scale)
        }

        // Only update if scale changed
        guard bufferScale != maxScale else {
            return
        }

        let oldScale = bufferScale
        bufferScale = maxScale

        // Apply buffer scale to surface (tells compositor what scale the buffer uses)
        wl_surface_set_buffer_scale(surface, maxScale)

        logger.debug("Scale changed: \(oldScale) -> \(maxScale)")

        // Emit scale change event to application
        if let inputState = inputState {
            inputState.enqueueEvent(.window(.scaleFactorChanged(
                id,
                oldFactor: Float(oldScale),
                newFactor: Float(maxScale)
            )))
        }

        // Resize EGL window to match new scale
        // The logical size stays the same, but the buffer size (logical * scale) changes
        if let eglWindow = eglWindow {
            let logicalWidth = Int32(currentSize.width)
            let logicalHeight = Int32(currentSize.height)
            // Note: wl_egl_window size should be in buffer pixels (logical * scale)
            // But Wayland handles this automatically via buffer_scale, so we keep logical size
            wl_egl_window_resize(eglWindow, logicalWidth, logicalHeight, 0, 0)
        }
    }

    public func requestRedraw() {
        wl_surface_damage(surface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(surface)
    }

    public func setDecorated(_ decorated: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Manual decoration toggle (libdecor manages automatically)"
        )
    }

    public func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        throw LuminaError.unsupportedPlatformFeature(
            feature: "Always-on-top (no standard protocol)"
        )
    }

    public func setTransparent(_ transparent: Bool) throws {
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
        WaylandCursor(window: self)
    }

    // MARK: - Internal Helpers for Decoration Strategies

    /// Get the wl_surface for decoration strategies
    nonisolated internal func getSurface() -> OpaquePointer? {
        return surface
    }

    /// Get the xdg_toplevel for decoration strategies
    /// Currently returns nil as we're using libdecor which manages xdg_toplevel internally
    nonisolated internal func getXdgToplevel() -> OpaquePointer? {
        // When using libdecor, we can extract xdg_toplevel from the frame
        guard let frame = frame,
              let getToplevel = LibdecorLoader.shared.libdecor_frame_get_xdg_toplevel else {
            return nil
        }
        return getToplevel(frame)
    }

    /// Handle window resize from decoration strategy
    nonisolated internal func handleResize(width: Int32, height: Int32) {
        currentSize = LogicalSize(width: Float(width), height: Float(height))

        if let eglWindow = eglWindow {
            wl_egl_window_resize(eglWindow, width, height, 0, 0)
        }

        if let userDataPtr = userDataPtr {
            userDataPtr.pointee.current_width = Float(width)
            userDataPtr.pointee.current_height = Float(height)
        }
    }

    /// Handle close request from decoration strategy
    nonisolated internal func handleCloseRequest() {
        // Post window close event
        // This would be handled by the application event loop
        logger.info("Close requested for window \(id)")
    }
}

// MARK: - C Callback Functions for wl_surface Listener

/// C callback for wl_surface.enter event.
/// Called when the surface enters an output (monitor).
private func surfaceHandleEnter(
    userData: UnsafeMutableRawPointer?,
    surface: OpaquePointer?,
    output: OpaquePointer?
) {
    guard let userData = userData,
          let output = output else {
        return
    }

    let window = Unmanaged<WaylandWindow>.fromOpaque(userData).takeUnretainedValue()

    // Look up the scale factor for this output from monitor tracker
    guard let monitorTracker = window.monitorTracker else {
        window.logger.error("No monitor tracker available for scale lookup")
        // Default to scale 1 if no monitor tracker
        window.outputScales.append(WaylandWindow.OutputScale(output: output, scale: 1))
        window.updateBufferScaleFromOutputs()
        return
    }

    // Find the scale for this output (use MainActor.assumeIsolated since we're in a display callback)
    let outputID = UInt64(Int(bitPattern: output))
    let outputScale: Int32 = MainActor.assumeIsolated {
        let monitors = monitorTracker.monitors

        // Match by output pointer (monitor ID stores the output name)
        for monitor in monitors {
            if monitor.id.value == UInt32(outputID & 0xFFFFFFFF) {
                return Int32(monitor.scaleFactor)
            }
        }
        return 1  // Default to scale 1 if not found
    }

    // Add to tracked outputs
    window.outputScales.append(WaylandWindow.OutputScale(output: output, scale: outputScale))

    window.logger.debug("Surface entered output (scale=\(outputScale)), total outputs: \(window.outputScales.count)")

    // Recalculate buffer scale
    window.updateBufferScaleFromOutputs()
}

/// C callback for wl_surface.leave event.
/// Called when the surface leaves an output (monitor).
private func surfaceHandleLeave(
    userData: UnsafeMutableRawPointer?,
    surface: OpaquePointer?,
    output: OpaquePointer?
) {
    guard let userData = userData,
          let output = output else {
        return
    }

    let window = Unmanaged<WaylandWindow>.fromOpaque(userData).takeUnretainedValue()

    // Remove this output from tracked outputs
    window.outputScales.removeAll { $0.output == output }

    window.logger.debug("Surface left output, remaining outputs: \(window.outputScales.count)")

    // Recalculate buffer scale
    window.updateBufferScaleFromOutputs()
}

/// C callback for wl_surface.preferred_buffer_scale event (Wayland protocol v6+).
/// This provides compositor's preferred buffer scale directly.
/// This is more direct than calculating from outputs and works better with fractional scaling.
private func surfaceHandlePreferredBufferScale(
    userData: UnsafeMutableRawPointer?,
    surface: OpaquePointer?,
    scale: Int32
) {
    guard let userData = userData else { return }

    let window = Unmanaged<WaylandWindow>.fromOpaque(userData).takeUnretainedValue()

    window.logger.debug("Compositor preferred buffer scale: \(scale)")

    // If compositor supports this event (protocol v6+), prefer it over calculated scale
    // Only update if scale actually changed
    guard window.bufferScale != scale else {
        return
    }

    let oldScale = window.bufferScale
    window.bufferScale = scale

    // Apply to surface
    wl_surface_set_buffer_scale(surface, scale)

    // Emit scale change event
    if let inputState = window.inputState {
        inputState.enqueueEvent(.window(.scaleFactorChanged(
            window.id,
            oldFactor: Float(oldScale),
            newFactor: Float(scale)
        )))
    }

    // Resize EGL window if needed
    if let eglWindow = window.eglWindow {
        let logicalWidth = Int32(window.currentSize.width)
        let logicalHeight = Int32(window.currentSize.height)
        wl_egl_window_resize(eglWindow, logicalWidth, logicalHeight, 0, 0)
    }
}

/// C callback for wl_surface.preferred_buffer_transform event (Wayland protocol v6+).
/// This provides compositor's preferred buffer transform.
private func surfaceHandlePreferredBufferTransform(
    userData: UnsafeMutableRawPointer?,
    surface: OpaquePointer?,
    transform: UInt32
) {
    // TODO: Handle buffer transform if needed
    // This is for rotation/flipping, not commonly used
}

// MARK: - WaylandCursor Implementation

/// Wayland implementation of LuminaCursor using wl_cursor_theme
@MainActor
private struct WaylandCursor: LuminaCursor {
    private weak var window: WaylandWindow?

    init(window: WaylandWindow) {
        self.window = window
    }

    func set(_ cursor: SystemCursor) {
        guard let window = window,
              let app = window.application,
              let inputState = window.inputState else {
            return
        }

        // Map SystemCursor to X cursor name (freedesktop.org cursor spec)
        let cursorName: String = switch cursor {
        case .arrow:
            "left_ptr"
        case .ibeam:
            "xterm"
        case .crosshair:
            "crosshair"
        case .hand:
            "hand2"
        case .resizeNS:
            "sb_v_double_arrow"
        case .resizeEW:
            "sb_h_double_arrow"
        case .resizeNESW:
            "bottom_left_corner"
        case .resizeNWSE:
            "bottom_right_corner"
        }

        // Avoid reloading the same cursor
        if app.cursorState.currentName == cursorName {
            return
        }

        var state = app.cursorState
        state.currentName = cursorName
        app.cursorState = state
        applyCursor(cursorName, app: app, inputState: inputState)
    }

    func hide() {
        guard let window = window,
              let app = window.application,
              let inputState = window.inputState else {
            return
        }

        var state = app.cursorState
        state.hidden = true
        app.cursorState = state

        // Set cursor to nil to hide it
        guard let pointer = inputState.state.pointer else {
            return
        }

        // Use the serial from the last pointer enter event
        let serial = inputState.state.pointerEnterSerial
        wl_pointer_set_cursor(pointer, serial, nil, 0, 0)
    }

    func show() {
        guard let window = window,
              let app = window.application,
              let inputState = window.inputState else {
            return
        }

        var state = app.cursorState
        state.hidden = false
        app.cursorState = state

        // Restore the current cursor
        if let cursorName = app.cursorState.currentName {
            applyCursor(cursorName, app: app, inputState: inputState)
        } else {
            // Default to arrow if no cursor was set
            applyCursor("left_ptr", app: app, inputState: inputState)
        }
    }

    private func applyCursor(_ cursorName: String, app: WaylandApplication, inputState: WaylandInputState) {
        let appCursorState = app.cursorState

        // Don't apply cursor if it's hidden
        if appCursorState.hidden {
            return
        }

        guard let cursorSurface = appCursorState.surface,
              let pointer = inputState.state.pointer else {
            return
        }

        let cursorLoader = app.cursorLoader

        // Determine which theme to use based on buffer scale
        let bufferScale = window?.bufferScale ?? 1
        let theme = (bufferScale > 1 && appCursorState.themeHiDPI != nil)
            ? appCursorState.themeHiDPI
            : appCursorState.theme

        guard let theme = theme,
              let getCursor = cursorLoader.wl_cursor_theme_get_cursor,
              let getBuffer = cursorLoader.wl_cursor_image_get_buffer else {
            return
        }

        // Load cursor from theme
        guard let wlCursorPtr = cursorName.withCString({ getCursor(theme, $0) }) else {
            print("Lumina: Failed to load cursor: \(cursorName)")
            return
        }

        // Bind OpaquePointer to WlCursor structure
        let wlCursor = UnsafeRawPointer(wlCursorPtr)
            .assumingMemoryBound(to: WaylandCursorLoader.WlCursor.self)
            .pointee

        // Get first image from cursor (TODO: handle animated cursors)
        let imageCount = Int(wlCursor.image_count)
        guard imageCount > 0,
              let imagesPtr = wlCursor.images,
              let imagePtr = imagesPtr[0] else {
            print("Lumina: Cursor has no images: \(cursorName)")
            return
        }

        // Get buffer for cursor image
        guard let buffer = getBuffer(imagePtr) else {
            print("Lumina: Failed to get buffer for cursor: \(cursorName)")
            return
        }

        // Bind image pointer to WlCursorImage structure
        let image = UnsafeRawPointer(imagePtr)
            .assumingMemoryBound(to: WaylandCursorLoader.WlCursorImage.self)
            .pointee

        // Apply cursor to surface
        let hotspotX = Int32(image.hotspot_x)
        let hotspotY = Int32(image.hotspot_y)

        wl_surface_attach(cursorSurface, buffer, 0, 0)
        wl_surface_damage(cursorSurface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(cursorSurface)

        // Set cursor on pointer (use serial from last enter event)
        let serial = inputState.state.pointerEnterSerial
        wl_pointer_set_cursor(pointer, serial, cursorSurface, hotspotX, hotspotY)
    }
}

extension WaylandCursor: @unchecked Sendable {}

#endif // os(Linux)
