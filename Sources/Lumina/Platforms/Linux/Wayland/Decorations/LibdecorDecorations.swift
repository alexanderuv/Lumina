// LibdecorDecorations.swift
// Lumina - Cross-platform windowing and input library
//
// Libdecor-based decorations using dynamically loaded libdecor library
// Provides best decoration experience with compositor-aware behavior

#if LUMINA_WAYLAND

import CWaylandClient

/// Libdecor decoration strategy using dynamically loaded libdecor
/// Tier 1 decoration method - best UX with compositor integration
final class LibdecorDecorations: DecorationStrategy {
    let decorationType: DecorationType = .libdecor

    // MARK: - State

    private weak var window: WaylandWindow?
    private let loader: LibdecorLoader
    private let display: OpaquePointer
    private var context: OpaquePointer?
    private var frame: OpaquePointer?
    private var frameInterface: UnsafeMutablePointer<libdecor_frame_interface>?
    private var libdecorInterface: UnsafeMutablePointer<libdecor_interface>?
    private let logger = LuminaLogger(label: "lumina.wayland.decorations.libdecor", level: .info)

    // MARK: - Initialization

    /// Create libdecor decoration strategy
    /// - Parameters:
    ///   - loader: The libdecor loader (must be already loaded)
    ///   - display: The wl_display connection
    init(loader: LibdecorLoader, display: OpaquePointer) {
        self.loader = loader
        self.display = display
    }

    // MARK: - DecorationStrategy Implementation

    func createDecorations(for window: WaylandWindow) throws {
        guard loader.isAvailable else {
            throw DecorationError.libdecorNotAvailable
        }

        self.window = window

        // Create libdecor context if needed
        if context == nil {
            try createLibdecorContext()
        }

        // Create libdecor frame
        try createLibdecorFrame()

        logger.debug("Created libdecor decorations")
    }

    func setTitle(_ title: String) {
        guard let frame = frame,
              let setTitle = loader.libdecor_frame_set_title else {
            return
        }

        title.withCString { titlePtr in
            setTitle(frame, titlePtr)
        }
    }

    func setMinimized() {
        guard let frame = frame,
              let setMinimized = loader.libdecor_frame_set_minimized else {
            return
        }

        setMinimized(frame)
    }

    func setMaximized() {
        guard let frame = frame,
              let setMaximized = loader.libdecor_frame_set_maximized else {
            return
        }

        setMaximized(frame)
    }

    func setFullscreen(output: OpaquePointer?) {
        guard let frame = frame,
              let setFullscreen = loader.libdecor_frame_set_fullscreen else {
            return
        }

        setFullscreen(frame, output)
    }

    func restore() {
        guard let frame = frame else { return }

        // Unset maximized and fullscreen
        if let unsetMaximized = loader.libdecor_frame_unset_maximized {
            unsetMaximized(frame)
        }
        if let unsetFullscreen = loader.libdecor_frame_unset_fullscreen {
            unsetFullscreen(frame)
        }
    }

    func resize(width: Int32, height: Int32) {
        // Resize is handled by libdecor's configure callback
        // We just need to create a new state and commit
        guard let frame = frame,
              let stateNew = loader.libdecor_state_new,
              let frameCommit = loader.libdecor_frame_commit,
              let stateFree = loader.libdecor_state_free else {
            return
        }

        guard let state = stateNew(width, height) else {
            return
        }

        frameCommit(frame, state, nil)
        stateFree(state)
    }

    func destroy() {
        // Destroy frame
        if let frame = frame,
           let frameUnref = loader.libdecor_frame_unref {
            frameUnref(frame)
            self.frame = nil
        }

        // Free frame interface
        if let iface = frameInterface {
            lumina_free_frame_interface(iface)
            frameInterface = nil
        }

        // Destroy context
        if let ctx = context,
           let ctxUnref = loader.libdecor_unref {
            ctxUnref(ctx)
            context = nil
        }

        // Free libdecor interface
        if let iface = libdecorInterface {
            lumina_free_libdecor_interface(iface)
            libdecorInterface = nil
        }

        logger.debug("Destroyed libdecor decorations")
    }

    // MARK: - Libdecor Setup

    private func createLibdecorContext() throws {
        guard let libdecorNew = loader.libdecor_new else {
            throw DecorationError.libdecorNotAvailable
        }

        // Create libdecor interface
        let iface = lumina_alloc_libdecor_interface { ctx, error, message in
            let errorStr = error == LIBDECOR_ERROR_COMPOSITOR_INCOMPATIBLE
                ? "compositor incompatible"
                : "invalid frame configuration"
            let msg = message.map { String(cString: $0) } ?? "unknown"
            print("Lumina: libdecor error: \(errorStr) - \(msg)")
        }

        guard let iface = iface else {
            throw DecorationError.libdecorNotAvailable
        }

        libdecorInterface = iface

        // Create libdecor context
        guard let ctx = libdecorNew(display, iface) else {
            lumina_free_libdecor_interface(iface)
            throw DecorationError.libdecorNotAvailable
        }

        context = ctx
        logger.debug("Created libdecor context")
    }

    private func createLibdecorFrame() throws {
        guard let ctx = context,
              let surface = window?.getSurface(),
              let decorate = loader.libdecor_decorate else {
            throw DecorationError.libdecorNotAvailable
        }

        // Create frame interface
        let iface = lumina_alloc_frame_interface(
            { frame, configuration, userData in
                // Configure callback
                guard let userData = userData else { return }
                let decorations = Unmanaged<LibdecorDecorations>.fromOpaque(userData).takeUnretainedValue()
                decorations.handleConfigure(frame: frame, configuration: configuration)
            },
            { frame, userData in
                // Close callback
                guard let userData = userData else { return }
                let decorations = Unmanaged<LibdecorDecorations>.fromOpaque(userData).takeUnretainedValue()
                decorations.handleClose()
            },
            { frame, userData in
                // Commit callback
                guard let userData = userData else { return }
                let decorations = Unmanaged<LibdecorDecorations>.fromOpaque(userData).takeUnretainedValue()
                decorations.handleCommit()
            }
        )

        guard let iface = iface else {
            throw DecorationError.libdecorNotAvailable
        }

        frameInterface = iface

        // Create frame
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard let frame = decorate(ctx, surface, iface, userData) else {
            lumina_free_frame_interface(iface)
            throw DecorationError.libdecorNotAvailable
        }

        self.frame = frame

        // Map the frame to make it visible
        if let frameMap = loader.libdecor_frame_map {
            frameMap(frame)
        }

        logger.debug("Created libdecor frame")
    }

    // MARK: - Libdecor Callbacks

    private func handleConfigure(frame: OpaquePointer?, configuration: OpaquePointer?) {
        guard let frame = frame,
              let configuration = configuration,
              let getContentSize = loader.libdecor_configuration_get_content_size,
              let stateNew = loader.libdecor_state_new,
              let frameCommit = loader.libdecor_frame_commit,
              let stateFree = loader.libdecor_state_free else {
            return
        }

        var width: Int32 = 0
        var height: Int32 = 0

        // Get content size from configuration
        if getContentSize(configuration, frame, &width, &height) {
            logger.debug("Configure: \(width)x\(height)")

            // Notify window of resize
            window?.handleResize(width: width, height: height)

            // Create state and commit
            if let state = stateNew(width, height) {
                frameCommit(frame, state, configuration)
                stateFree(state)
            }
        } else {
            // No size specified, use current size
            if let state = stateNew(800, 600) {  // Default size
                frameCommit(frame, state, configuration)
                stateFree(state)
            }
        }
    }

    private func handleClose() {
        logger.info("Close requested")
        window?.handleCloseRequest()
    }

    private func handleCommit() {
        // Commit the surface
        if let surface = window?.getSurface() {
            wl_surface_commit(surface)
        }
    }

    /// Dispatch libdecor events
    /// Should be called from the event loop
    func dispatch(timeout: Int32 = 0) -> Int32 {
        guard let ctx = context,
              let dispatch = loader.libdecor_dispatch else {
            return -1
        }

        return dispatch(ctx, timeout)
    }

    deinit {
        destroy()
    }
}

#endif // LUMINA_WAYLAND
