// ServerSideDecorations.swift
// Lumina - Cross-platform windowing and input library
//
// Server-side decorations using zxdg_decoration_manager_v1 protocol
// Compositor draws the title bar, borders, and window controls

#if LUMINA_WAYLAND

import CWaylandClient

/// Server-side decoration strategy using zxdg_decoration_manager_v1
/// The compositor draws window decorations (title bar, borders, controls)
final class ServerSideDecorations: DecorationStrategy {
    let decorationType: DecorationType = .serverSide

    // MARK: - State

    private weak var window: WaylandWindow?
    private let decorationManager: OpaquePointer
    private var toplevelDecoration: OpaquePointer?
    private var decorationListener: zxdg_toplevel_decoration_v1_listener?
    private let logger = LuminaLogger(label: "lumina.wayland.decorations.ssd", level: .info)

    // MARK: - Initialization

    /// Create server-side decoration strategy
    /// - Parameters:
    ///   - decorationManager: The zxdg_decoration_manager_v1 global
    ///   - window: The window to decorate
    init(decorationManager: OpaquePointer) {
        self.decorationManager = decorationManager
    }

    // MARK: - DecorationStrategy Implementation

    func createDecorations(for window: WaylandWindow) throws {
        self.window = window

        // Get the xdg_toplevel from the window
        guard let xdgToplevel = window.getXdgToplevel() else {
            throw DecorationError.invalidConfiguration
        }

        // Create toplevel decoration
        guard let decoration = zxdg_decoration_manager_v1_get_toplevel_decoration(
            decorationManager,
            xdgToplevel
        ) else {
            throw DecorationError.ssdNotSupported
        }

        self.toplevelDecoration = decoration

        // Set up listener
        setupListener()

        // Request server-side mode
        zxdg_toplevel_decoration_v1_set_mode(
            decoration,
            ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue
        )
    }

    func setTitle(_ title: String) {
        // Title is set on xdg_toplevel directly, not through decorations
        // This is handled by the window itself
    }

    func setMinimized() {
        // Minimize is handled by xdg_toplevel, not decorations
    }

    func setMaximized() {
        // Maximize is handled by xdg_toplevel, not decorations
    }

    func setFullscreen(output: OpaquePointer?) {
        // Fullscreen is handled by xdg_toplevel, not decorations
    }

    func restore() {
        // Restore is handled by xdg_toplevel, not decorations
    }

    func resize(width: Int32, height: Int32) {
        // Server-side decorations don't need manual resize handling
        // The compositor handles decoration sizing automatically
    }

    func destroy() {
        if let decoration = toplevelDecoration {
            zxdg_toplevel_decoration_v1_destroy(decoration)
            toplevelDecoration = nil
        }
        decorationListener = nil
    }

    // MARK: - Listener Setup

    private func setupListener() {
        guard let decoration = toplevelDecoration else { return }

        // Create listener
        var listener = zxdg_toplevel_decoration_v1_listener(
            configure: { userData, decoration, mode in
                guard let userData = userData else { return }
                let ssd = Unmanaged<ServerSideDecorations>.fromOpaque(userData).takeUnretainedValue()
                ssd.handleConfigure(mode: mode)
            }
        )

        self.decorationListener = listener

        // Add listener
        let userData = Unmanaged.passUnretained(self).toOpaque()
        _ = withUnsafePointer(to: &listener) { listenerPtr in
            zxdg_toplevel_decoration_v1_add_listener(
                decoration,
                listenerPtr,
                userData
            )
        }
    }

    // MARK: - Event Handlers

    private func handleConfigure(mode: UInt32) {
        switch mode {
        case ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE.rawValue:
            logger.error("Compositor wants client-side decorations, but we requested server-side")
        case ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue:
            // Server-side decorations confirmed
            break
        default:
            logger.error("Unknown decoration mode: \(mode)")
        }
    }

    deinit {
        destroy()
    }
}

#endif // LUMINA_WAYLAND
