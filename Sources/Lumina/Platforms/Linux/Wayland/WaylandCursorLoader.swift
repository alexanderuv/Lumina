#if os(Linux) && LUMINA_WAYLAND

import Foundation
import CWaylandClient

/// Dynamic loader for libwayland-cursor.so.0
///
/// Wayland cursor support requires dynamically loading cursor theme functionality
/// which provides cursor theme loading and standard cursor shapes. We dynamically
/// load this at runtime to avoid compile-time dependencies.
///
/// **Architecture:**
/// - Singleton pattern (shared instance)
/// - Loads libwayland-cursor.so.0 via dlopen
/// - Provides function pointers for cursor operations
/// - Thread-safe initialization
///
/// **Usage:**
/// ```swift
/// let loader = WaylandCursorLoader.shared
/// if loader.isAvailable {
///     let theme = loader.wl_cursor_theme_load?("default", 24, shm)
///     let cursor = loader.wl_cursor_theme_get_cursor?(theme, "left_ptr")
/// }
/// ```
@MainActor
final class WaylandCursorLoader {
    // MARK: - Singleton

    static let shared = WaylandCursorLoader()

    // MARK: - State

    private nonisolated(unsafe) var handle: UnsafeMutableRawPointer?
    private(set) var isAvailable: Bool = false
    private let logger = LuminaLogger(label: "lumina.wayland.cursor", level: .info)

    // MARK: - Function Pointers

    /// wl_cursor_theme_load(const char *name, int size, struct wl_shm *shm)
    typealias WlCursorThemeLoadFunc = @convention(c) (
        UnsafePointer<CChar>?,  // theme name (NULL for default)
        Int32,                   // cursor size
        OpaquePointer?           // wl_shm*
    ) -> OpaquePointer?

    /// wl_cursor_theme_destroy(struct wl_cursor_theme *theme)
    typealias WlCursorThemeDestroyFunc = @convention(c) (OpaquePointer?) -> Void

    /// wl_cursor_theme_get_cursor(struct wl_cursor_theme *theme, const char *name)
    typealias WlCursorThemeGetCursorFunc = @convention(c) (
        OpaquePointer?,          // wl_cursor_theme*
        UnsafePointer<CChar>?    // cursor name
    ) -> OpaquePointer?

    /// wl_cursor_image_get_buffer(struct wl_cursor_image *image)
    typealias WlCursorImageGetBufferFunc = @convention(c) (OpaquePointer?) -> OpaquePointer?

    // MARK: - wl_cursor Structures (from wayland-cursor.h)

    /// Cursor image structure
    struct WlCursorImage {
        var width: UInt32
        var height: UInt32
        var hotspot_x: UInt32
        var hotspot_y: UInt32
        var delay: UInt32
    }

    /// Cursor structure (contains array of images for animated cursors)
    struct WlCursor {
        var image_count: UInt32
        var images: UnsafeMutablePointer<OpaquePointer?>?
        var name: UnsafeMutablePointer<CChar>?
    }

    nonisolated(unsafe) private(set) var wl_cursor_theme_load: WlCursorThemeLoadFunc?
    nonisolated(unsafe) private(set) var wl_cursor_theme_destroy: WlCursorThemeDestroyFunc?
    nonisolated(unsafe) private(set) var wl_cursor_theme_get_cursor: WlCursorThemeGetCursorFunc?
    nonisolated(unsafe) private(set) var wl_cursor_image_get_buffer: WlCursorImageGetBufferFunc?

    // MARK: - Initialization

    private init() {
        loadLibrary()
    }

    private func loadLibrary() {
        // Try to load libwayland-cursor.so.0
        guard let handle = dlopen("libwayland-cursor.so.0", RTLD_LAZY | RTLD_LOCAL) else {
            logger.logError("Failed to load libwayland-cursor.so.0")
            if let error = dlerror() {
                logger.logError("dlopen error: \(String(cString: error))")
            }
            return
        }

        self.handle = handle

        // Load function pointers
        guard let themeLoad = loadSymbol(handle, "wl_cursor_theme_load", WlCursorThemeLoadFunc.self),
              let themeDestroy = loadSymbol(handle, "wl_cursor_theme_destroy", WlCursorThemeDestroyFunc.self),
              let themeGetCursor = loadSymbol(handle, "wl_cursor_theme_get_cursor", WlCursorThemeGetCursorFunc.self),
              let imageGetBuffer = loadSymbol(handle, "wl_cursor_image_get_buffer", WlCursorImageGetBufferFunc.self) else {
            logger.logError("Failed to load required symbols")
            dlclose(handle)
            self.handle = nil
            return
        }

        self.wl_cursor_theme_load = themeLoad
        self.wl_cursor_theme_destroy = themeDestroy
        self.wl_cursor_theme_get_cursor = themeGetCursor
        self.wl_cursor_image_get_buffer = imageGetBuffer

        self.isAvailable = true
        logger.logInfo("Successfully loaded libwayland-cursor.so.0")
    }

    private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, _ type: T.Type) -> T? {
        guard let symbol = dlsym(handle, name) else {
            logger.logError("Failed to load symbol: \(name)")
            if let error = dlerror() {
                logger.logError("dlsym error: \(String(cString: error))")
            }
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    // MARK: - Cleanup

    deinit {
        if let handle = handle {
            dlclose(handle)
        }
    }
}

// MARK: - Sendable Conformance

extension WaylandCursorLoader: @unchecked Sendable {}

#endif // os(Linux) && LUMINA_WAYLAND
