// DecorationStrategy.swift
// Lumina - Cross-platform windowing and input library
//
// Defines the strategy pattern for window decorations on Wayland.
// 3-tier decoration fallback: libdecor → SSD → CSD

#if LUMINA_WAYLAND

import CWaylandClient

/// Type of window decoration being used
enum DecorationType {
    case libdecor      // Dynamic libdecor (best UX, compositor-aware)
    case serverSide    // Server-side decorations via zxdg_decoration_manager_v1
    case clientSide    // Client-side decorations via wl_subcompositor
    case none          // No decorations (borderless window)
}

/// Protocol for window decoration strategies on Wayland
/// Abstracts different decoration methods to allow runtime selection
protocol DecorationStrategy: AnyObject {
    /// The type of decoration this strategy provides
    var decorationType: DecorationType { get }

    /// Create decorations for the given window
    /// - Parameter window: The window to decorate
    /// - Throws: DecorationError if decoration creation fails
    func createDecorations(for window: WaylandWindow) throws

    /// Set the window title
    /// - Parameter title: The new window title
    func setTitle(_ title: String)

    /// Set the window to minimized state
    func setMinimized()

    /// Set the window to maximized state
    func setMaximized()

    /// Set the window to fullscreen state
    /// - Parameter output: Optional output to use for fullscreen, nil for current output
    func setFullscreen(output: OpaquePointer?)

    /// Restore the window to normal state (not minimized, maximized, or fullscreen)
    func restore()

    /// Handle window resize
    /// - Parameters:
    ///   - width: New width in pixels
    ///   - height: New height in pixels
    func resize(width: Int32, height: Int32)

    /// Destroy the decorations
    func destroy()
}

/// Errors that can occur during decoration creation or management
enum DecorationError: Error {
    case libdecorNotAvailable
    case ssdNotSupported
    case csdNotSupported
    case noDecorationMethodAvailable
    case surfaceCreationFailed
    case invalidConfiguration

    var localizedDescription: String {
        switch self {
        case .libdecorNotAvailable:
            return "libdecor library not available for dynamic loading"
        case .ssdNotSupported:
            return "Server-side decorations not supported by compositor"
        case .csdNotSupported:
            return "Client-side decorations not supported (missing wl_subcompositor)"
        case .noDecorationMethodAvailable:
            return "No decoration method available (tried libdecor, SSD, and CSD)"
        case .surfaceCreationFailed:
            return "Failed to create surface for decorations"
        case .invalidConfiguration:
            return "Invalid decoration configuration received"
        }
    }
}

/// No-op decoration strategy for borderless windows
final class NoDecorations: DecorationStrategy {
    let decorationType: DecorationType = .none

    func createDecorations(for window: WaylandWindow) throws {
        // No decorations to create
    }

    func setTitle(_ title: String) {
        // No title bar to update
    }

    func setMinimized() {
        // No-op for borderless windows
    }

    func setMaximized() {
        // No-op for borderless windows
    }

    func setFullscreen(output: OpaquePointer?) {
        // Fullscreen still works without decorations
        // This would be handled by xdg_toplevel directly
    }

    func restore() {
        // No-op for borderless windows
    }

    func resize(width: Int32, height: Int32) {
        // No decorations to resize
    }

    func destroy() {
        // Nothing to clean up
    }
}

#endif // LUMINA_WAYLAND
