// ClientSideDecorations.swift
// Lumina - Cross-platform windowing and input library
//
// Client-side decorations using wl_subcompositor
// Creates subsurfaces for title bar and borders, handles mouse events

#if LUMINA_WAYLAND

import CWaylandClient

/// Client-side decoration strategy using wl_subcompositor
/// Creates subsurfaces for title bar (24px) and borders (4px)
final class ClientSideDecorations: DecorationStrategy {
    let decorationType: DecorationType = .clientSide

    // MARK: - Constants

    private let titleBarHeight: Int32 = 24
    private let borderWidth: Int32 = 4
    private let borderColor: (UInt8, UInt8, UInt8) = (128, 128, 128)  // Gray borders

    // MARK: - State

    private weak var window: WaylandWindow?
    private weak var inputState: WaylandInputState?
    private let compositor: OpaquePointer
    private let subcompositor: OpaquePointer
    private let shm: OpaquePointer
    private var viewporter: OpaquePointer?

    // Subsurfaces
    private var topSurface: OpaquePointer?      // Title bar
    private var leftSurface: OpaquePointer?     // Left border
    private var rightSurface: OpaquePointer?    // Right border
    private var bottomSurface: OpaquePointer?   // Bottom border

    // Subsurface objects
    private var topSubsurface: OpaquePointer?
    private var leftSubsurface: OpaquePointer?
    private var rightSubsurface: OpaquePointer?
    private var bottomSubsurface: OpaquePointer?

    // Shared buffer for all borders (1x1 pixel scaled via viewport)
    private var borderBuffer: OpaquePointer?
    private var borderBufferSize: Int = 0

    private var currentWidth: Int32 = 0
    private var currentHeight: Int32 = 0
    private let logger = LuminaLogger(label: "lumina.wayland.decorations.csd", level: .info)

    // MARK: - Initialization

    /// Create client-side decoration strategy
    /// - Parameters:
    ///   - compositor: The wl_compositor global
    ///   - subcompositor: The wl_subcompositor global
    ///   - shm: The wl_shm global for buffer creation
    ///   - viewporter: Optional wp_viewporter for efficient scaling
    init(compositor: OpaquePointer, subcompositor: OpaquePointer, shm: OpaquePointer, viewporter: OpaquePointer? = nil) {
        self.compositor = compositor
        self.subcompositor = subcompositor
        self.shm = shm
        self.viewporter = viewporter
    }

    // MARK: - DecorationStrategy Implementation

    func createDecorations(for window: WaylandWindow) throws {
        self.window = window
        self.inputState = window.application?.inputState

        guard let mainSurface = window.getSurface() else {
            throw DecorationError.surfaceCreationFailed
        }

        // Create shared 1x1 pixel buffer for borders
        try createBorderBuffer()

        // Create subsurfaces for each edge
        try createSubsurface(surface: &topSurface, subsurface: &topSubsurface, parent: mainSurface)
        try createSubsurface(surface: &leftSurface, subsurface: &leftSubsurface, parent: mainSurface)
        try createSubsurface(surface: &rightSurface, subsurface: &rightSubsurface, parent: mainSurface)
        try createSubsurface(surface: &bottomSurface, subsurface: &bottomSubsurface, parent: mainSurface)

        // Set subsurfaces as synchronized
        if let top = topSubsurface { wl_subsurface_set_sync(top) }
        if let left = leftSubsurface { wl_subsurface_set_sync(left) }
        if let right = rightSubsurface { wl_subsurface_set_sync(right) }
        if let bottom = bottomSubsurface { wl_subsurface_set_sync(bottom) }

        // Attach buffer to all surfaces
        attachBufferToSurface(topSurface)
        attachBufferToSurface(leftSurface)
        attachBufferToSurface(rightSurface)
        attachBufferToSurface(bottomSurface)

        // Register decoration surfaces with input state for pointer events
        if let inputState = inputState {
            if let surf = topSurface { inputState.registerDecorationSurface(surf, windowID: window.id, area: .titleBar) }
            if let surf = leftSurface { inputState.registerDecorationSurface(surf, windowID: window.id, area: .leftBorder) }
            if let surf = rightSurface { inputState.registerDecorationSurface(surf, windowID: window.id, area: .rightBorder) }
            if let surf = bottomSurface { inputState.registerDecorationSurface(surf, windowID: window.id, area: .bottomBorder) }
        }

        logger.debug("Created client-side decorations")
    }

    func setTitle(_ title: String) {
        // For now, we don't draw text on the title bar
        // Future: Could use cairo/pango to render title text
    }

    func setMinimized() {
        // Minimize is handled by xdg_toplevel, not decorations
    }

    func setMaximized() {
        // Maximize is handled by xdg_toplevel, not decorations
    }

    func setFullscreen(output: OpaquePointer?) {
        // In fullscreen mode, hide decorations
        hideSurface(topSurface)
        hideSurface(leftSurface)
        hideSurface(rightSurface)
        hideSurface(bottomSurface)
    }

    func restore() {
        // Show decorations again
        showSurface(topSurface)
        showSurface(leftSurface)
        showSurface(rightSurface)
        showSurface(bottomSurface)
    }

    func resize(width: Int32, height: Int32) {
        currentWidth = width
        currentHeight = height
        updateDecorationPositions()
    }

    func destroy() {
        // Unregister decoration surfaces from input state
        if let inputState = inputState {
            if let surf = topSurface { inputState.unregisterDecorationSurface(surf) }
            if let surf = leftSurface { inputState.unregisterDecorationSurface(surf) }
            if let surf = rightSurface { inputState.unregisterDecorationSurface(surf) }
            if let surf = bottomSurface { inputState.unregisterDecorationSurface(surf) }
        }

        // Destroy subsurfaces
        if let sub = topSubsurface { wl_subsurface_destroy(sub) }
        if let sub = leftSubsurface { wl_subsurface_destroy(sub) }
        if let sub = rightSubsurface { wl_subsurface_destroy(sub) }
        if let sub = bottomSubsurface { wl_subsurface_destroy(sub) }

        // Destroy surfaces
        if let surf = topSurface { wl_surface_destroy(surf) }
        if let surf = leftSurface { wl_surface_destroy(surf) }
        if let surf = rightSurface { wl_surface_destroy(surf) }
        if let surf = bottomSurface { wl_surface_destroy(surf) }

        // Destroy buffer
        if let buffer = borderBuffer {
            wl_buffer_destroy(buffer)
            borderBuffer = nil
        }

        topSurface = nil
        leftSurface = nil
        rightSurface = nil
        bottomSurface = nil
        topSubsurface = nil
        leftSubsurface = nil
        rightSubsurface = nil
        bottomSubsurface = nil

        logger.debug("Destroyed client-side decorations")
    }

    // MARK: - Helper Methods

    private func createSubsurface(
        surface: inout OpaquePointer?,
        subsurface: inout OpaquePointer?,
        parent: OpaquePointer
    ) throws {
        // Create surface
        guard let surf = wl_compositor_create_surface(compositor) else {
            throw DecorationError.surfaceCreationFailed
        }
        surface = surf

        // Create subsurface
        guard let sub = wl_subcompositor_get_subsurface(subcompositor, surf, parent) else {
            wl_surface_destroy(surf)
            throw DecorationError.csdNotSupported
        }
        subsurface = sub

        // Place subsurface above parent
        wl_subsurface_place_above(sub, parent)
    }

    private func createBorderBuffer() throws {
        // Create 1x1 pixel buffer
        let width: Int32 = 1
        let height: Int32 = 1
        let stride = width * 4  // ARGB8888
        let size = stride * height

        // Create shared memory file
        let fd = lumina_memfd_create("lumina-csd-border", 0)
        guard fd >= 0 else {
            throw DecorationError.surfaceCreationFailed
        }

        // Resize file
        guard ftruncate(fd, off_t(size)) == 0 else {
            close(fd)
            throw DecorationError.surfaceCreationFailed
        }

        // Map memory
        let data = mmap(nil, Int(size), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard data != nil, data != UnsafeMutableRawPointer(bitPattern: -1) else {  // MAP_FAILED is (void*)-1
            close(fd)
            throw DecorationError.surfaceCreationFailed
        }

        // Write pixel color (ARGB8888 format)
        let pixelData = data!.assumingMemoryBound(to: UInt32.self)
        let alpha: UInt32 = 255
        let red = UInt32(borderColor.0)
        let green = UInt32(borderColor.1)
        let blue = UInt32(borderColor.2)
        pixelData[0] = (alpha << 24) | (red << 16) | (green << 8) | blue

        munmap(data, Int(size))

        // Create wl_shm_pool
        guard let pool = wl_shm_create_pool(shm, fd, size) else {
            close(fd)
            throw DecorationError.surfaceCreationFailed
        }

        // Create buffer
        guard let buffer = wl_shm_pool_create_buffer(
            pool,
            0,  // offset
            width,
            height,
            stride,
            UInt32(WL_SHM_FORMAT_ARGB8888.rawValue)
        ) else {
            wl_shm_pool_destroy(pool)
            close(fd)
            throw DecorationError.surfaceCreationFailed
        }

        wl_shm_pool_destroy(pool)
        close(fd)

        borderBuffer = buffer
        borderBufferSize = Int(size)
    }

    private func attachBufferToSurface(_ surface: OpaquePointer?) {
        guard let surface = surface, let buffer = borderBuffer else { return }

        wl_surface_attach(surface, buffer, 0, 0)
        wl_surface_commit(surface)
    }

    private func updateDecorationPositions() {
        guard let mainSurface = window?.getSurface() else { return }

        // Top (title bar): x=0, y=-24, w=width, h=24
        if let sub = topSubsurface {
            wl_subsurface_set_position(sub, 0, -titleBarHeight)
        }
        if let surf = topSurface, let viewporter = viewporter {
            // Use viewport to scale 1x1 buffer to full width x title bar height
            if let viewport = wp_viewporter_get_viewport(viewporter, surf) {
                wp_viewport_set_destination(viewport, currentWidth, titleBarHeight)
                wl_surface_commit(surf)
            }
        }

        // Left border: x=-4, y=-24, w=4, h=height+24
        if let sub = leftSubsurface {
            wl_subsurface_set_position(sub, -borderWidth, -titleBarHeight)
        }
        if let surf = leftSurface, let viewporter = viewporter {
            if let viewport = wp_viewporter_get_viewport(viewporter, surf) {
                wp_viewport_set_destination(viewport, borderWidth, currentHeight + titleBarHeight)
                wl_surface_commit(surf)
            }
        }

        // Right border: x=width, y=-24, w=4, h=height+24
        if let sub = rightSubsurface {
            wl_subsurface_set_position(sub, currentWidth, -titleBarHeight)
        }
        if let surf = rightSurface, let viewporter = viewporter {
            if let viewport = wp_viewporter_get_viewport(viewporter, surf) {
                wp_viewport_set_destination(viewport, borderWidth, currentHeight + titleBarHeight)
                wl_surface_commit(surf)
            }
        }

        // Bottom border: x=-4, y=height, w=width+8, h=4
        if let sub = bottomSubsurface {
            wl_subsurface_set_position(sub, -borderWidth, currentHeight)
        }
        if let surf = bottomSurface, let viewporter = viewporter {
            if let viewport = wp_viewporter_get_viewport(viewporter, surf) {
                wp_viewport_set_destination(viewport, currentWidth + borderWidth * 2, borderWidth)
                wl_surface_commit(surf)
            }
        }

        // Commit main surface to apply subsurface changes
        wl_surface_commit(mainSurface)
    }

    private func hideSurface(_ surface: OpaquePointer?) {
        guard let surface = surface else { return }
        wl_surface_attach(surface, nil, 0, 0)
        wl_surface_commit(surface)
    }

    private func showSurface(_ surface: OpaquePointer?) {
        attachBufferToSurface(surface)
    }

    deinit {
        destroy()
    }
}

#endif // LUMINA_WAYLAND
