#if os(macOS)
import AppKit
import Foundation

/// Window delegate to handle close events
@MainActor
private final class MacWindowDelegate: NSObject, NSWindowDelegate {
    private let windowID: WindowID
    private let closeCallback: WindowCloseCallback?

    init(windowID: WindowID, closeCallback: WindowCloseCallback?) {
        self.windowID = windowID
        self.closeCallback = closeCallback
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Notify the application that this window is closing
        // This will unregister the window from the app's registry
        closeCallback?(windowID)
    }
}

/// macOS implementation of PlatformWindow using NSWindow.
///
/// This implementation wraps NSWindow and provides Lumina's cross-platform
/// window interface. It handles coordinate system conversion (AppKit uses
/// bottom-left origin, Lumina uses top-left), DPI scaling, and window state
/// management.
@MainActor
internal struct MacWindow: LuminaWindow {
    let id: WindowID
    private var nsWindow: NSWindow
    private var delegate: MacWindowDelegate

    /// Expose the NSWindow's window number for event routing.
    internal var windowNumber: Int {
        nsWindow.windowNumber
    }

    /// Create a new macOS window.
    ///
    /// - Parameters:
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether the window can be resized by the user
    ///   - monitor: Optional monitor to create the window on (uses primary if nil)
    ///   - closeCallback: Optional callback to invoke when the window closes
    /// - Returns: Result containing MacWindow or LuminaError
    internal static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor? = nil,
        closeCallback: WindowCloseCallback? = nil
    ) -> Result<MacWindow, LuminaError> {
        // Create content rect for the window
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(size.width),
            height: CGFloat(size.height)
        )

        // Configure window style mask
        var styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable
        ]

        if resizable {
            styleMask.insert(.resizable)
        }

        // Create NSWindow
        let nsWindow = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        nsWindow.title = title

        // Position the window based on monitor parameter or center it
        if let monitor = monitor {
            // Position window on the specified monitor
            let targetScreen = NSScreen.screens.first { screen in
                // Match based on screen frame position
                let screenFrame = screen.frame
                let monitorPhysical = monitor.physicalPosition
                return Int(screenFrame.origin.x) == monitorPhysical.x &&
                       Int(screenFrame.origin.y) == monitorPhysical.y
            } ?? NSScreen.main

            if let screen = targetScreen {
                // Position window on the target screen (offset from screen's origin)
                let screenFrame = screen.frame
                let windowFrame = nsWindow.frame
                let x = screenFrame.origin.x + 100
                let y = screenFrame.origin.y + screenFrame.height - windowFrame.height - 100
                nsWindow.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                nsWindow.center()
            }
        } else {
            nsWindow.center()  // Center on screen initially
        }

        // Enable automatic background color (system-appropriate)
        nsWindow.backgroundColor = .windowBackgroundColor

        // Create window ID first (needed for delegate)
        let windowID = WindowID()

        // Create and set delegate to handle close events
        let delegate = MacWindowDelegate(windowID: windowID, closeCallback: closeCallback)
        nsWindow.delegate = delegate

        // Create window wrapper
        let macWindow = MacWindow(id: windowID, nsWindow: nsWindow, delegate: delegate)

        return .success(macWindow)
    }

    mutating func show() {
        nsWindow.makeKeyAndOrderFront(nil)
    }

    mutating func hide() {
        nsWindow.orderOut(nil)
    }

    consuming func close() {
        nsWindow.close()
    }

    mutating func setTitle(_ title: String) {
        nsWindow.title = title
    }

    func size() -> LogicalSize {
        let contentSize = nsWindow.contentRect(forFrameRect: nsWindow.frame).size
        return LogicalSize(
            width: Float(contentSize.width),
            height: Float(contentSize.height)
        )
    }

    mutating func resize(_ size: LogicalSize) {
        let currentFrame = nsWindow.frame
        let currentContentRect = nsWindow.contentRect(forFrameRect: currentFrame)

        // Calculate new content rect with same origin
        let newContentRect = NSRect(
            x: currentContentRect.origin.x,
            y: currentContentRect.origin.y,
            width: CGFloat(size.width),
            height: CGFloat(size.height)
        )

        // Convert content rect to frame rect (includes title bar)
        let newFrame = nsWindow.frameRect(forContentRect: newContentRect)

        // Set new frame, don't animate
        nsWindow.setFrame(newFrame, display: true, animate: false)
    }

    func position() -> LogicalPosition {
        // AppKit uses bottom-left origin, Lumina uses top-left
        // Convert from AppKit screen coordinates to top-left origin

        let frame = nsWindow.frame
        let screen = nsWindow.screen ?? NSScreen.main!
        let screenFrame = screen.frame

        // Get top-left corner in AppKit coordinates
        let topLeftY = frame.origin.y + frame.size.height

        // Convert to top-left origin coordinate system
        let x = frame.origin.x
        let y = screenFrame.size.height - topLeftY

        return LogicalPosition(
            x: Float(x),
            y: Float(y)
        )
    }

    mutating func moveTo(_ position: LogicalPosition) {
        // Convert from Lumina's top-left origin to AppKit's bottom-left origin

        let screen = nsWindow.screen ?? NSScreen.main!
        let screenFrame = screen.frame
        let windowFrame = nsWindow.frame

        // Convert top-left Y to bottom-left Y
        let topLeftY = CGFloat(position.y)
        let bottomLeftY = screenFrame.size.height - topLeftY - windowFrame.size.height

        let newOrigin = NSPoint(
            x: CGFloat(position.x),
            y: bottomLeftY
        )

        nsWindow.setFrameOrigin(newOrigin)
    }

    mutating func setMinSize(_ size: LogicalSize?) {
        if let size = size {
            nsWindow.contentMinSize = NSSize(
                width: CGFloat(size.width),
                height: CGFloat(size.height)
            )
        } else {
            // Reset to no minimum (use small default)
            nsWindow.contentMinSize = NSSize(width: 0, height: 0)
        }
    }

    mutating func setMaxSize(_ size: LogicalSize?) {
        if let size = size {
            nsWindow.contentMaxSize = NSSize(
                width: CGFloat(size.width),
                height: CGFloat(size.height)
            )
        } else {
            // Reset to no maximum (use very large size)
            nsWindow.contentMaxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    mutating func requestFocus() {
        nsWindow.makeKeyAndOrderFront(nil)
    }

    func scaleFactor() -> Float {
        Float(nsWindow.backingScaleFactor)
    }
}

// MARK: - Sendable Conformance

// MacWindow is @MainActor isolated, so it's safe to conform to Sendable
// NSWindow is a reference type, but all access is isolated to the main actor
extension MacWindow: @unchecked Sendable {}

#endif
