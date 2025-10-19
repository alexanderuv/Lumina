/// Internal window registry for mapping platform-specific window handles to WindowIDs.
///
/// This generic helper is used by platform implementations to track active windows
/// and resolve WindowIDs when processing events. Each platform uses a different
/// handle type (NSWindow.windowNumber on macOS, HWND on Windows).
///
/// Thread Safety: Must only be accessed from @MainActor.
@MainActor
internal struct WindowRegistry<PlatformHandle: Hashable> {
    private var mapping: [PlatformHandle: WindowID] = [:]

    /// Register a new window with its platform handle.
    ///
    /// - Parameters:
    ///   - handle: Platform-specific window handle
    ///   - id: Lumina WindowID to associate with this handle
    mutating func register(_ handle: PlatformHandle, id: WindowID) {
        mapping[handle] = id
    }

    /// Unregister a window by its platform handle.
    ///
    /// - Parameter handle: Platform-specific window handle to remove
    mutating func unregister(_ handle: PlatformHandle) {
        mapping.removeValue(forKey: handle)
    }

    /// Look up the WindowID for a platform handle.
    ///
    /// - Parameter handle: Platform-specific window handle
    /// - Returns: The associated WindowID, or nil if not registered
    func windowID(for handle: PlatformHandle) -> WindowID? {
        mapping[handle]
    }

    /// Check if the registry is empty (no windows registered).
    var isEmpty: Bool {
        mapping.isEmpty
    }
}
