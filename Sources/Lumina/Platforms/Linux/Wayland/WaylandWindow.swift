#if os(Linux)
import CWaylandClient
import Foundation
import Glibc

/// Wayland implementation of LuminaWindow using libdecor.
///
/// This implementation provides window management on Linux Wayland systems using
/// the libdecor library for automatic server-side/client-side decoration handling.
/// It follows the SDL3/GLFW pattern where libdecor is the primary decoration path,
/// providing compatibility with all Wayland compositors (GNOME, KDE, Sway, Weston, etc.).
///
/// **Architecture:**
/// - Uses `libdecor_frame` instead of raw `xdg_toplevel` for window management
/// - libdecor automatically selects SSD (via xdg-decoration) or CSD (manual rendering)
/// - Integrates with WaylandApplication's libdecor event loop via `libdecor_dispatch()`
/// - Manages `wl_surface` for rendering content via shared memory buffers
///
/// **Do not instantiate this type directly.** Windows are created through
/// `LuminaApp.createWindow()`.
///
/// Example:
/// ```swift
/// var app = try createLuminaApp(.wayland)
/// var window = try app.createWindow(
///     title: "Wayland Window",
///     size: LogicalSize(width: 800, height: 600),
///     resizable: true,
///     monitor: nil
/// ).get()
/// window.show()
/// ```
///
/// References:
/// - [libdecor architecture](https://xeechou.net/posts/libdecor/)
/// - [SDL3 Wayland backend](https://github.com/libsdl-org/SDL/tree/main/src/video/wayland)
/// - [GLFW Wayland backend](https://github.com/glfw/glfw/tree/master/src)
@MainActor
public struct WaylandWindow: LuminaWindow {
    /// Unique Lumina window ID
    public let id: WindowID

    /// libdecor frame (owns decoration logic)
    private let frame: OpaquePointer

    /// Wayland surface (content rendering)
    private let surface: OpaquePointer

    /// Wayland compositor (for creating surfaces)
    private let compositor: OpaquePointer

    /// Shared memory pool for buffer allocation
    private let shmPool: OpaquePointer?

    /// Current buffer attached to surface
    private var buffer: OpaquePointer?

    /// Current window size (logical coordinates)
    private var currentSize: LogicalSize

    /// Whether window is currently visible
    private var isVisible: Bool = false

    /// Minimum size constraint
    private var minSize: LogicalSize?

    /// Maximum size constraint
    private var maxSize: LogicalSize?

    /// Reference to application for event posting (weak to avoid retain cycles)
    /// Note: This is stored as an opaque pointer to avoid circular dependencies
    private weak var application: AnyObject?

    /// User data pointer for libdecor callbacks (C struct, must be freed on window close)
    private let userDataPtr: UnsafeMutablePointer<LuminaWindowUserData>

    /// Frame interface struct pointer (heap-allocated, must be released on window close)
    private let frameInterfacePtr: UnsafeMutablePointer<libdecor_frame_interface>

    /// Create a new Wayland window using libdecor.
    ///
    /// This is an internal method called by WaylandApplication.createWindow().
    ///
    /// - Parameters:
    ///   - decorContext: libdecor context from application
    ///   - compositor: wl_compositor for creating surfaces
    ///   - shm: wl_shm for shared memory buffer allocation
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether window can be resized
    ///   - application: Reference to application for event posting
    /// - Returns: Newly created window
    /// - Throws: `LuminaError.windowCreationFailed` if creation fails
    static func create(
        decorContext: OpaquePointer,
        compositor: OpaquePointer,
        shm: OpaquePointer,
        title: String,
        size: LogicalSize,
        resizable: Bool,
        application: AnyObject?
    ) throws -> WaylandWindow {
        // 1. Create Wayland surface
        guard let surface = wl_compositor_create_surface(compositor) else {
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create wl_surface"
            )
        }

        // 2. Create shared memory pool for rendering buffers
        // This is a simplified implementation - production code would use a proper buffer pool
        let stride = Int32(size.width) * 4  // ARGB8888 format (4 bytes per pixel)
        let bufferSize = stride * Int32(size.height)

        // Create anonymous file for shared memory
        let fd = createAnonymousFile(size: Int(bufferSize))
        guard fd >= 0 else {
            wl_surface_destroy(surface)
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create shared memory file"
            )
        }

        // Create wl_shm_pool
        guard let pool = wl_shm_create_pool(shm, fd, bufferSize) else {
            _ = Glibc.close(fd)
            wl_surface_destroy(surface)
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create wl_shm_pool"
            )
        }

        // Create buffer from pool
        let buffer = wl_shm_pool_create_buffer(
            pool,
            0,  // offset
            Int32(size.width),
            Int32(size.height),
            stride,
            WL_SHM_FORMAT_ARGB8888.rawValue
        )

        _ = Glibc.close(fd)

        if buffer == nil {
            wl_shm_pool_destroy(pool)
            wl_surface_destroy(surface)
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create wl_buffer"
            )
        }

        // 3. Set up libdecor frame interface callbacks
        // These callbacks are invoked by libdecor to handle configure events, close requests, etc.
        let windowID = WindowID()

        // Create user data to pass to callbacks (C struct)
        let userDataPtr = UnsafeMutablePointer<LuminaWindowUserData>.allocate(capacity: 1)
        withUnsafeBytes(of: windowID.id.uuid) { uuidBytes in
            let high = uuidBytes.load(fromByteOffset: 0, as: UInt64.self)
            let low = uuidBytes.load(fromByteOffset: 8, as: UInt64.self)
            userDataPtr.pointee = LuminaWindowUserData(
                window_id_high: high,
                window_id_low: low,
                current_width: Float(size.width),
                current_height: Float(size.height)
            )
        }

        // Configure libdecor_frame_interface using C helper
        // Swift automatically bridges these closures to C function pointers
        guard let frameInterfacePtr = lumina_alloc_frame_interface(
            { frame, configuration, userData in
                handleConfigure(frame: frame, configuration: configuration, userData: userData)
            },
            { frame, userData in
                handleClose(frame: frame, userData: userData)
            },
            { frame, userData in
                handleCommit(frame: frame, userData: userData)
            }
        ) else {
            wl_buffer_destroy(buffer)
            wl_shm_pool_destroy(pool)
            wl_surface_destroy(surface)
            userDataPtr.deallocate()
            throw LuminaError.windowCreationFailed(
                reason: "Failed to allocate libdecor_frame_interface"
            )
        }

        // 4. Create libdecor frame (replaces xdg-surface + xdg-toplevel)
        guard let frame = libdecor_decorate(
            decorContext,
            surface,
            frameInterfacePtr,
            userDataPtr
        ) else {
            wl_buffer_destroy(buffer)
            wl_shm_pool_destroy(pool)
            wl_surface_destroy(surface)
            // Free the C struct user data since frame creation failed
            userDataPtr.deallocate()
            // Free the interface pointer using C helper
            lumina_free_frame_interface(frameInterfacePtr)
            throw LuminaError.windowCreationFailed(
                reason: "Failed to create libdecor_frame"
            )
        }

        // 5. Set window properties
        libdecor_frame_set_title(frame, title)
        libdecor_frame_set_app_id(frame, "com.lumina.app")

        // Set min/max size constraints if not resizable
        if !resizable {
            libdecor_frame_set_min_content_size(
                frame,
                Int32(size.width),
                Int32(size.height)
            )
            libdecor_frame_set_max_content_size(
                frame,
                Int32(size.width),
                Int32(size.height)
            )
        }

        // 6. Attach buffer to surface for initial render
        wl_surface_attach(surface, buffer, 0, 0)
        wl_surface_damage(surface, 0, 0, Int32.max, Int32.max)
        wl_surface_commit(surface)

        // 7. Create and return WaylandWindow (frameInterfacePtr must be stored to keep it alive)
        return WaylandWindow(
            id: windowID,
            frame: frame,
            surface: surface,
            compositor: compositor,
            shmPool: pool,
            buffer: buffer,
            currentSize: size,
            isVisible: false,
            minSize: resizable ? nil : size,
            maxSize: resizable ? nil : size,
            application: application,
            userDataPtr: userDataPtr,
            frameInterfacePtr: frameInterfacePtr
        )
    }

    // MARK: - LuminaWindow Protocol Implementation

    public mutating func show() {
        // Map the libdecor frame (makes window visible)
        libdecor_frame_map(frame)
        isVisible = true
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
        if let buffer = buffer {
            wl_buffer_destroy(buffer)
        }
        if let pool = shmPool {
            wl_shm_pool_destroy(pool)
        }
        libdecor_frame_unref(frame)
        wl_surface_destroy(surface)

        // Free the C struct user data
        userDataPtr.deallocate()

        // Free the frame interface pointer using C helper
        lumina_free_frame_interface(frameInterfacePtr)
    }

    public mutating func setTitle(_ title: String) {
        libdecor_frame_set_title(frame, title)
        // Commit the change
        libdecor_frame_commit(frame, nil, nil)
    }

    public func size() -> LogicalSize {
        return currentSize
    }

    public mutating func resize(_ size: LogicalSize) {
        // Update current size
        currentSize = size

        // Recreate buffer with new size
        let stride = Int32(size.width) * 4
        _ = stride * Int32(size.height)  // bufferSize calculated but not used in simplified implementation

        // Create new buffer
        if let pool = shmPool {
            // Destroy old buffer
            if let oldBuffer = buffer {
                wl_buffer_destroy(oldBuffer)
            }

            // Create new buffer from pool
            // Note: This is simplified - production code would resize the pool if needed
            buffer = wl_shm_pool_create_buffer(
                pool,
                0,
                Int32(size.width),
                Int32(size.height),
                stride,
                WL_SHM_FORMAT_ARGB8888.rawValue
            )

            // Attach new buffer
            if let newBuffer = buffer {
                wl_surface_attach(surface, newBuffer, 0, 0)
                wl_surface_damage(surface, 0, 0, Int32.max, Int32.max)
                wl_surface_commit(surface)
            }
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
        // Damage the entire surface to trigger redraw
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

// MARK: - libdecor Frame Callbacks

// User data is defined as a C struct in CWaylandClient/shim.h (LuminaWindowUserData)
// This keeps the FFI boundary clean and avoids Swift reference counting issues
//
// Callbacks are passed as closures directly to lumina_alloc_frame_interface()
// Swift automatically bridges non-capturing closures to C function pointers

/// Handle configure event from libdecor
private func handleConfigure(
    frame: OpaquePointer?,
    configuration: OpaquePointer?,
    userData: UnsafeMutableRawPointer?
) {
    guard let frame = frame,
          let configuration = configuration,
          let userData = userData else {
        return
    }

    let userDataPtr = userData.assumingMemoryBound(to: LuminaWindowUserData.self)

    // Get configured size from libdecor
    var width: Int32 = 0
    var height: Int32 = 0

    // Query content size from configuration
    if !libdecor_configuration_get_content_size(
        configuration,
        frame,
        &width,
        &height
    ) {
        // No size specified, use current size from user data
        width = Int32(userDataPtr.pointee.current_width)
        height = Int32(userDataPtr.pointee.current_height)
    }

    // Update current size in user data
    userDataPtr.pointee.current_width = Float(width)
    userDataPtr.pointee.current_height = Float(height)

    // Create libdecor state with new size
    let state = libdecor_state_new(width, height)
    defer { libdecor_state_free(state) }

    // Commit the configuration
    libdecor_frame_commit(frame, state, configuration)

    // TODO: Post window resized event to application
}

/// Handle close request from libdecor (user clicked close button)
private func handleClose(
    frame: OpaquePointer?,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData = userData else {
        return
    }

    let userDataPtr = userData.assumingMemoryBound(to: LuminaWindowUserData.self)
    // Window ID is available in userDataPtr.pointee.window_id_high/low

    // TODO: Post window close event to application
}

/// Handle commit request from libdecor
private func handleCommit(
    frame: OpaquePointer?,
    userData: UnsafeMutableRawPointer?
) {
    // This callback indicates that the frame is ready to commit
    // Usually we would commit the surface here, but we already commit
    // in resize() and other operations
}

// MARK: - Helper Functions

/// Create an anonymous file for shared memory
///
/// Creates a temporary file in memory (using memfd_create on Linux) for use
/// with wl_shm. This is the standard pattern for Wayland buffer allocation.
///
/// - Parameter size: Size of the file in bytes
/// - Returns: File descriptor, or -1 on error
private func createAnonymousFile(size: Int) -> Int32 {
    // Try memfd_create (Linux 3.17+)
    #if os(Linux)
    let fd = memfd_create("lumina-shm", 0)
    if fd >= 0 {
        if ftruncate(fd, off_t(size)) == 0 {
            return fd
        }
        _ = Glibc.close(fd)
    }
    #endif

    // Fallback: use /tmp
    let template = "/tmp/lumina-shm-XXXXXX"
    return template.withCString { templatePtr in
        // Create mutable copy of template
        var mutableTemplate = [CChar](repeating: 0, count: Int(strlen(templatePtr)) + 1)
        strcpy(&mutableTemplate, templatePtr)

        let fd = mkstemp(&mutableTemplate)
        if fd >= 0 {
            // Unlink immediately so file is deleted when closed
            unlink(mutableTemplate)

            if ftruncate(fd, off_t(size)) == 0 {
                return fd
            }
            _ = Glibc.close(fd)
        }
        return -1
    }
}

// MARK: - Wayland C API Helpers

/// Helper to create memfd file descriptor
@_silgen_name("memfd_create")
private func memfd_create(_ name: UnsafePointer<CChar>, _ flags: UInt32) -> Int32

#endif // os(Linux)
