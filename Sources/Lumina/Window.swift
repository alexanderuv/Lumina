/// Cross-platform window abstraction.
///
/// Window represents a desktop window with a title bar, content area, and
/// standard window controls (minimize, maximize, close). Each window has a
/// unique identifier and can be shown, hidden, moved, and resized.
///
/// Windows are created via the static create() factory method, which returns
/// a Result type for explicit error handling. The ~Copyable constraint prevents
/// window handle duplication.
///
/// Thread Safety: All Window methods must be called from the main thread.
/// The @MainActor annotation enforces this at compile time.
///
/// Example:
/// ```swift
/// let result = Window.create(
///     title: "My Application",
///     size: LogicalSize(width: 1024, height: 768),
///     resizable: true
/// )
///
/// switch result {
/// case .success(var window):
///     window.show()
///     print("Window created with ID: \(window.id)")
/// case .failure(let error):
///     print("Failed to create window: \(error)")
/// }
/// ```
@MainActor
public struct Window: ~Copyable {
    /// Unique identifier for this window.
    ///
    /// The ID is stable for the lifetime of the window and is used to
    /// associate events with specific window instances.
    public let id: WindowID

    #if os(macOS)
    private var backend: MacWindow
    #elseif os(Windows)
    private var backend: WinWindow
    #else
    #error("Unsupported platform")
    #endif

    /// Create a new window.
    ///
    /// This factory method creates a platform-specific window with the specified
    /// attributes. The window is created in a hidden state; call show() to make
    /// it visible.
    ///
    /// Platform Notes:
    /// - macOS: Creates NSWindow with appropriate style mask
    /// - Windows: Creates HWND with CreateWindowEx
    /// - Both platforms respect DPI scaling automatically
    ///
    /// Monitor Selection:
    /// - If monitor is specified, the window will be created on that monitor
    /// - If monitor is nil (default), the primary monitor is used
    /// - The window's DPI scaling is automatically adjusted to match the target monitor
    ///
    /// - Parameters:
    ///   - title: Window title displayed in the title bar
    ///   - size: Initial logical size of the window's content area
    ///   - resizable: Whether the window can be resized by the user (default: true)
    ///   - monitor: The monitor to create the window on (default: nil for primary)
    ///
    /// - Returns: Result containing Window or LuminaError
    ///
    /// Example:
    /// ```swift
    /// // Create window on primary monitor
    /// let window = try Window.create(
    ///     title: "Hello, Lumina!",
    ///     size: LogicalSize(width: 800, height: 600)
    /// ).get()
    ///
    /// // Create window on specific monitor
    /// let monitors = try Monitor.all()
    /// let secondMonitor = monitors[1]
    /// let window2 = try Window.create(
    ///     title: "Second Window",
    ///     size: LogicalSize(width: 800, height: 600),
    ///     monitor: secondMonitor
    /// ).get()
    /// ```
    public static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool = true,
        monitor: Monitor? = nil
    ) -> Result<Window, LuminaError> {
        #if os(macOS)
        return MacWindow.create(title: title, size: size, resizable: resizable, monitor: monitor)
            .map { macWindow in
                Window(id: macWindow.id, backend: macWindow)
            }
        #elseif os(Windows)
        return WinWindow.create(title: title, size: size, resizable: resizable, monitor: monitor)
            .map { winWindow in
                Window(id: winWindow.id, backend: winWindow)
            }
        #endif
    }

    /// Private initializer (use create() factory method).
    #if os(macOS)
    private init(id: WindowID, backend: MacWindow) {
        self.id = id
        self.backend = backend
    }
    #elseif os(Windows)
    private init(id: WindowID, backend: WinWindow) {
        self.id = id
        self.backend = backend
    }
    #endif

    /// Show the window and make it visible.
    ///
    /// If the window is already visible, this has no effect. On macOS, this
    /// also brings the window to the front and gives it keyboard focus.
    ///
    /// Example:
    /// ```swift
    /// var window = try Window.create(
    ///     title: "App",
    ///     size: LogicalSize(width: 800, height: 600)
    /// ).get()
    /// window.show()
    /// ```
    public mutating func show() {
        backend.show()
    }

    /// Hide the window (make it invisible).
    ///
    /// The window's state is preserved and it can be shown again later.
    /// Hidden windows continue to exist and maintain their properties.
    ///
    /// Example:
    /// ```swift
    /// window.hide()  // Window disappears but still exists
    /// window.show()  // Window reappears in same state
    /// ```
    public mutating func hide() {
        backend.hide()
    }

    /// Close the window and release resources (consumes self).
    ///
    /// After calling this method, the window is destroyed and can no longer
    /// be used. This method consumes ownership of the window.
    ///
    /// Platform Notes:
    /// - macOS: Calls close() on NSWindow
    /// - Windows: Calls DestroyWindow(hwnd)
    ///
    /// Example:
    /// ```swift
    /// let window = try Window.create(
    ///     title: "Temporary",
    ///     size: LogicalSize(width: 400, height: 300)
    /// ).get()
    /// window.show()
    /// // ... do something ...
    /// window.close()  // Window is destroyed, variable is consumed
    /// ```
    public consuming func close() {
        backend.close()
    }

    /// Set the window title.
    ///
    /// Updates the text displayed in the window's title bar.
    ///
    /// - Parameter title: The new window title
    ///
    /// Example:
    /// ```swift
    /// window.setTitle("Untitled Document")
    /// // User makes changes...
    /// window.setTitle("My Document *")  // Indicate unsaved changes
    /// ```
    public mutating func setTitle(_ title: String) {
        backend.setTitle(title)
    }

    /// Get the current window size (logical coordinates).
    ///
    /// Returns the size of the window's content area in logical points,
    /// excluding the title bar and borders. This is the area available
    /// for drawing content.
    ///
    /// - Returns: Current logical size of the window content area
    ///
    /// Example:
    /// ```swift
    /// let currentSize = window.size()
    /// print("Window is \(currentSize.width) × \(currentSize.height) points")
    /// ```
    public func size() -> LogicalSize {
        backend.size()
    }

    /// Resize the window programmatically.
    ///
    /// Changes the window's content area to the specified size. The window's
    /// position is preserved. If min/max size constraints are set, the final
    /// size will be clamped to those bounds.
    ///
    /// - Parameter size: The new logical size for the window
    ///
    /// Example:
    /// ```swift
    /// window.resize(LogicalSize(width: 1920, height: 1080))
    /// ```
    public mutating func resize(_ size: LogicalSize) {
        backend.resize(size)
    }

    /// Get the current window position (screen coordinates).
    ///
    /// Returns the position of the window's top-left corner in screen
    /// coordinates (logical points). Origin (0, 0) is at the top-left
    /// corner of the primary display.
    ///
    /// - Returns: Current logical position of the window
    ///
    /// Example:
    /// ```swift
    /// let position = window.position()
    /// print("Window is at (\(position.x), \(position.y))")
    /// ```
    public func position() -> LogicalPosition {
        backend.position()
    }

    /// Move the window to a new position.
    ///
    /// Changes the position of the window's top-left corner in screen
    /// coordinates. The window's size is preserved.
    ///
    /// - Parameter position: The new logical position for the window's top-left corner
    ///
    /// Example:
    /// ```swift
    /// // Center window on screen (approximate)
    /// window.moveTo(LogicalPosition(x: 400, y: 300))
    /// ```
    public mutating func moveTo(_ position: LogicalPosition) {
        backend.moveTo(position)
    }

    /// Set minimum window size constraint.
    ///
    /// Prevents the window from being resized smaller than the specified size.
    /// Pass nil to remove the constraint.
    ///
    /// - Parameter size: Minimum logical size, or nil to remove constraint
    ///
    /// Example:
    /// ```swift
    /// // Prevent window from being smaller than 400×300
    /// window.setMinSize(LogicalSize(width: 400, height: 300))
    ///
    /// // Later, remove the constraint
    /// window.setMinSize(nil)
    /// ```
    public mutating func setMinSize(_ size: LogicalSize?) {
        backend.setMinSize(size)
    }

    /// Set maximum window size constraint.
    ///
    /// Prevents the window from being resized larger than the specified size.
    /// Pass nil to remove the constraint.
    ///
    /// - Parameter size: Maximum logical size, or nil to remove constraint
    ///
    /// Example:
    /// ```swift
    /// // Prevent window from being larger than 1920×1080
    /// window.setMaxSize(LogicalSize(width: 1920, height: 1080))
    ///
    /// // Later, remove the constraint
    /// window.setMaxSize(nil)
    /// ```
    public mutating func setMaxSize(_ size: LogicalSize?) {
        backend.setMaxSize(size)
    }

    /// Request keyboard focus for this window.
    ///
    /// Makes this window the active window that receives keyboard input.
    /// On macOS, this also brings the window to the front.
    ///
    /// Example:
    /// ```swift
    /// // Bring window to front when user performs an action
    /// window.requestFocus()
    /// ```
    public mutating func requestFocus() {
        backend.requestFocus()
    }

    /// Get the current scale factor (DPI) for this window.
    ///
    /// Returns the ratio of physical pixels to logical points. Common values:
    /// - 1.0: Standard DPI (96 DPI on Windows, 72 DPI on macOS)
    /// - 2.0: Retina/HiDPI (192 DPI on Windows, 144 DPI on macOS)
    ///
    /// The scale factor can change when:
    /// - Window is moved between monitors with different DPI settings
    /// - System DPI settings are changed
    ///
    /// Applications should use logical sizes for all window operations; the
    /// scale factor is primarily needed for rendering or pixel-perfect layouts.
    ///
    /// - Returns: Current scale factor for this window
    ///
    /// Example:
    /// ```swift
    /// let scaleFactor = window.scaleFactor()
    /// let logicalSize = window.size()
    /// let physicalSize = logicalSize.toPhysical(scaleFactor: scaleFactor)
    /// print("Physical pixels: \(physicalSize.width) × \(physicalSize.height)")
    /// ```
    public func scaleFactor() -> Float {
        backend.scaleFactor()
    }
}
