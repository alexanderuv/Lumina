// LibdecorLoader.swift
// Lumina - Cross-platform windowing and input library
//
// Dynamic loader for libdecor library
// Loads libdecor at runtime via dlopen to avoid compile-time dependency

#if LUMINA_WAYLAND

import CWaylandClient

/// Dynamic loader for libdecor library
/// Loads libdecor at runtime instead of linking at compile time
final class LibdecorLoader: @unchecked Sendable {
    // MARK: - Function Pointer Types

    // Core libdecor functions
    typealias libdecor_new_fn = @convention(c) (
        _ wl_display: OpaquePointer?,
        _ interface: UnsafePointer<libdecor_interface>?
    ) -> OpaquePointer?

    typealias libdecor_unref_fn = @convention(c) (
        _ context: OpaquePointer?
    ) -> Void

    typealias libdecor_get_fd_fn = @convention(c) (
        _ context: OpaquePointer?
    ) -> Int32

    typealias libdecor_dispatch_fn = @convention(c) (
        _ context: OpaquePointer?,
        _ timeout: Int32
    ) -> Int32

    // Frame management
    typealias libdecor_decorate_fn = @convention(c) (
        _ context: OpaquePointer?,
        _ surface: OpaquePointer?,
        _ interface: UnsafePointer<libdecor_frame_interface>?,
        _ user_data: UnsafeMutableRawPointer?
    ) -> OpaquePointer?

    typealias libdecor_frame_unref_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_set_app_id_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ app_id: UnsafePointer<CChar>?
    ) -> Void

    typealias libdecor_frame_set_title_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ title: UnsafePointer<CChar>?
    ) -> Void

    typealias libdecor_frame_set_minimized_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_set_maximized_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_unset_maximized_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_set_fullscreen_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ output: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_unset_fullscreen_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_map_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_commit_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ state: OpaquePointer?,
        _ configuration: OpaquePointer?
    ) -> Void

    typealias libdecor_frame_set_min_content_size_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ width: Int32,
        _ height: Int32
    ) -> Void

    typealias libdecor_frame_set_max_content_size_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ width: Int32,
        _ height: Int32
    ) -> Void

    typealias libdecor_frame_set_capabilities_fn = @convention(c) (
        _ frame: OpaquePointer?,
        _ capabilities: UInt32
    ) -> Void

    typealias libdecor_frame_get_xdg_toplevel_fn = @convention(c) (
        _ frame: OpaquePointer?
    ) -> OpaquePointer?

    // Configuration functions
    typealias libdecor_configuration_get_content_size_fn = @convention(c) (
        _ configuration: OpaquePointer?,
        _ frame: OpaquePointer?,
        _ width: UnsafeMutablePointer<Int32>?,
        _ height: UnsafeMutablePointer<Int32>?
    ) -> Bool

    typealias libdecor_configuration_get_window_state_fn = @convention(c) (
        _ configuration: OpaquePointer?,
        _ window_state: UnsafeMutablePointer<UInt32>?
    ) -> Bool

    // State management
    typealias libdecor_state_new_fn = @convention(c) (
        _ width: Int32,
        _ height: Int32
    ) -> OpaquePointer?

    typealias libdecor_state_free_fn = @convention(c) (
        _ state: OpaquePointer?
    ) -> Void

    // MARK: - Function Pointers

    var libdecor_new: libdecor_new_fn?
    var libdecor_unref: libdecor_unref_fn?
    var libdecor_get_fd: libdecor_get_fd_fn?
    var libdecor_dispatch: libdecor_dispatch_fn?

    var libdecor_decorate: libdecor_decorate_fn?
    var libdecor_frame_unref: libdecor_frame_unref_fn?
    var libdecor_frame_set_app_id: libdecor_frame_set_app_id_fn?
    var libdecor_frame_set_title: libdecor_frame_set_title_fn?
    var libdecor_frame_set_minimized: libdecor_frame_set_minimized_fn?
    var libdecor_frame_set_maximized: libdecor_frame_set_maximized_fn?
    var libdecor_frame_unset_maximized: libdecor_frame_unset_maximized_fn?
    var libdecor_frame_set_fullscreen: libdecor_frame_set_fullscreen_fn?
    var libdecor_frame_unset_fullscreen: libdecor_frame_unset_fullscreen_fn?
    var libdecor_frame_map: libdecor_frame_map_fn?
    var libdecor_frame_commit: libdecor_frame_commit_fn?
    var libdecor_frame_set_min_content_size: libdecor_frame_set_min_content_size_fn?
    var libdecor_frame_set_max_content_size: libdecor_frame_set_max_content_size_fn?
    var libdecor_frame_set_capabilities: libdecor_frame_set_capabilities_fn?
    var libdecor_frame_get_xdg_toplevel: libdecor_frame_get_xdg_toplevel_fn?

    var libdecor_configuration_get_content_size: libdecor_configuration_get_content_size_fn?
    var libdecor_configuration_get_window_state: libdecor_configuration_get_window_state_fn?

    var libdecor_state_new: libdecor_state_new_fn?
    var libdecor_state_free: libdecor_state_free_fn?

    // MARK: - State

    private var handle: UnsafeMutableRawPointer?
    private(set) var isAvailable: Bool = false

    // MARK: - Singleton

    static let shared = LibdecorLoader()

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Loading

    /// Attempt to load libdecor library dynamically
    /// - Returns: true if successfully loaded, false otherwise
    func load() -> Bool {
        guard !isAvailable else {
            print("[LibdecorLoader] Already loaded")
            return true
        }

        // Try to load libdecor-0.so.0
        guard let handle = dlopen("libdecor-0.so.0", RTLD_LAZY) else {
            let error = String(cString: dlerror())
            print("[LibdecorLoader] Failed to load libdecor-0.so.0: \(error)")
            return false
        }

        self.handle = handle
        print("[LibdecorLoader] Successfully loaded libdecor-0.so.0")

        // Load all function pointers
        guard loadSymbols() else {
            print("[LibdecorLoader] Failed to load all symbols")
            unload()
            return false
        }

        isAvailable = true
        print("[LibdecorLoader] All symbols loaded successfully")
        return true
    }

    /// Unload the library and reset state
    func unload() {
        if let handle = handle {
            dlclose(handle)
            self.handle = nil
        }

        // Clear all function pointers
        libdecor_new = nil
        libdecor_unref = nil
        libdecor_get_fd = nil
        libdecor_dispatch = nil
        libdecor_decorate = nil
        libdecor_frame_unref = nil
        libdecor_frame_set_app_id = nil
        libdecor_frame_set_title = nil
        libdecor_frame_set_minimized = nil
        libdecor_frame_set_maximized = nil
        libdecor_frame_unset_maximized = nil
        libdecor_frame_set_fullscreen = nil
        libdecor_frame_unset_fullscreen = nil
        libdecor_frame_map = nil
        libdecor_frame_commit = nil
        libdecor_frame_set_min_content_size = nil
        libdecor_frame_set_max_content_size = nil
        libdecor_frame_set_capabilities = nil
        libdecor_frame_get_xdg_toplevel = nil
        libdecor_configuration_get_content_size = nil
        libdecor_configuration_get_window_state = nil
        libdecor_state_new = nil
        libdecor_state_free = nil

        isAvailable = false
        print("[LibdecorLoader] Unloaded library")
    }

    // MARK: - Symbol Loading

    private func loadSymbols() -> Bool {
        guard let handle = handle else { return false }

        // Load each function pointer
        libdecor_new = loadSymbol("libdecor_new", from: handle)
        libdecor_unref = loadSymbol("libdecor_unref", from: handle)
        libdecor_get_fd = loadSymbol("libdecor_get_fd", from: handle)
        libdecor_dispatch = loadSymbol("libdecor_dispatch", from: handle)
        libdecor_decorate = loadSymbol("libdecor_decorate", from: handle)
        libdecor_frame_unref = loadSymbol("libdecor_frame_unref", from: handle)
        libdecor_frame_set_app_id = loadSymbol("libdecor_frame_set_app_id", from: handle)
        libdecor_frame_set_title = loadSymbol("libdecor_frame_set_title", from: handle)
        libdecor_frame_set_minimized = loadSymbol("libdecor_frame_set_minimized", from: handle)
        libdecor_frame_set_maximized = loadSymbol("libdecor_frame_set_maximized", from: handle)
        libdecor_frame_unset_maximized = loadSymbol("libdecor_frame_unset_maximized", from: handle)
        libdecor_frame_set_fullscreen = loadSymbol("libdecor_frame_set_fullscreen", from: handle)
        libdecor_frame_unset_fullscreen = loadSymbol("libdecor_frame_unset_fullscreen", from: handle)
        libdecor_frame_map = loadSymbol("libdecor_frame_map", from: handle)
        libdecor_frame_commit = loadSymbol("libdecor_frame_commit", from: handle)
        libdecor_frame_set_min_content_size = loadSymbol("libdecor_frame_set_min_content_size", from: handle)
        libdecor_frame_set_max_content_size = loadSymbol("libdecor_frame_set_max_content_size", from: handle)
        libdecor_frame_set_capabilities = loadSymbol("libdecor_frame_set_capabilities", from: handle)
        libdecor_frame_get_xdg_toplevel = loadSymbol("libdecor_frame_get_xdg_toplevel", from: handle)
        libdecor_configuration_get_content_size = loadSymbol("libdecor_configuration_get_content_size", from: handle)
        libdecor_configuration_get_window_state = loadSymbol("libdecor_configuration_get_window_state", from: handle)
        libdecor_state_new = loadSymbol("libdecor_state_new", from: handle)
        libdecor_state_free = loadSymbol("libdecor_state_free", from: handle)

        // Verify critical functions are loaded
        guard libdecor_new != nil,
              libdecor_decorate != nil,
              libdecor_frame_commit != nil else {
            print("[LibdecorLoader] Failed to load critical symbols")
            return false
        }

        return true
    }

    private func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else {
            let error = String(cString: dlerror())
            print("[LibdecorLoader] Failed to load symbol '\(name)': \(error)")
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    deinit {
        unload()
    }
}

#endif // LUMINA_WAYLAND
