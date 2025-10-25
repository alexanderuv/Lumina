#if os(macOS)
import AppKit
import Foundation

/// Window delegate to handle window events
@MainActor
private final class MacWindowDelegate: NSObject, NSWindowDelegate {
    private let windowID: WindowID
    private let closeCallback: WindowCloseCallback?
    private let eventQueue: WindowEventQueue

    init(windowID: WindowID, closeCallback: WindowCloseCallback?, eventQueue: WindowEventQueue) {
        self.windowID = windowID
        self.closeCallback = closeCallback
        self.eventQueue = eventQueue
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

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let contentSize = window.contentRect(forFrameRect: window.frame).size
        let size = LogicalSize(width: Float(contentSize.width), height: Float(contentSize.height))
        eventQueue.append(.resized(windowID, size))
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let frame = window.frame
        let screen = window.screen ?? NSScreen.main!
        let screenFrame = screen.frame

        // Convert from AppKit's bottom-left to top-left origin
        let topLeftY = frame.origin.y + frame.size.height
        let x = frame.origin.x
        let y = screenFrame.size.height - topLeftY

        let position = LogicalPosition(x: Float(x), y: Float(y))
        eventQueue.append(.moved(windowID, position))
    }

    func windowDidBecomeKey(_ notification: Notification) {
        eventQueue.append(.focused(windowID))
    }

    func windowDidResignKey(_ notification: Notification) {
        eventQueue.append(.unfocused(windowID))
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Get old and new scale factors
        if let userInfo = notification.userInfo,
           let oldScaleNumber = userInfo[NSWindow.oldScaleFactorUserInfoKey] as? NSNumber {
            let oldScale = Float(oldScaleNumber.doubleValue)
            let newScale = Float(window.backingScaleFactor)

            if oldScale != newScale {
                eventQueue.append(.scaleFactorChanged(windowID, oldFactor: oldScale, newFactor: newScale))
            }
        }
    }
}

/// macOS implementation of PlatformWindow using NSWindow.
///
/// This implementation wraps NSWindow and provides Lumina's cross-platform
/// window interface. It handles coordinate system conversion (AppKit uses
/// bottom-left origin, Lumina uses top-left), DPI scaling, and window state
/// management.
@MainActor
public final class MacWindow: LuminaWindow {
    public let id: WindowID
    private var nsWindow: NSWindow
    private var delegate: MacWindowDelegate

    /// Expose the NSWindow's window number for event routing.
    internal var windowNumber: Int {
        nsWindow.windowNumber
    }

    /// Private initializer - use create() instead
    private init(id: WindowID, nsWindow: NSWindow, delegate: MacWindowDelegate) {
        self.id = id
        self.nsWindow = nsWindow
        self.delegate = delegate
    }

    /// Create a new macOS window.
    ///
    /// - Parameters:
    ///   - title: Window title
    ///   - size: Initial logical size
    ///   - resizable: Whether the window can be resized by the user
    ///   - monitor: Optional monitor to create the window on (uses primary if nil)
    ///   - closeCallback: Optional callback to invoke when the window closes
    ///   - eventQueue: Queue for posting window events (moved, resized, focus, etc.)
    /// - Returns: Newly created MacWindow
    /// - Throws: LuminaError if window creation fails
    internal static func create(
        title: String,
        size: LogicalSize,
        resizable: Bool,
        monitor: Monitor? = nil,
        closeCallback: WindowCloseCallback? = nil,
        eventQueue: WindowEventQueue
    ) throws -> MacWindow {
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

        // Create and set delegate to handle window events
        let delegate = MacWindowDelegate(windowID: windowID, closeCallback: closeCallback, eventQueue: eventQueue)
        nsWindow.delegate = delegate

        // Create window wrapper
        let macWindow = MacWindow(id: windowID, nsWindow: nsWindow, delegate: delegate)

        return macWindow
    }

    public func show() {
        nsWindow.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        nsWindow.orderOut(nil)
    }

    public consuming func close() {
        nsWindow.close()
    }

    public func setTitle(_ title: String) {
        nsWindow.title = title
    }

    public func size() -> LogicalSize {
        let contentSize = nsWindow.contentRect(forFrameRect: nsWindow.frame).size
        return LogicalSize(
            width: Float(contentSize.width),
            height: Float(contentSize.height)
        )
    }

    public func resize(_ size: LogicalSize) {
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

    public func position() -> LogicalPosition {
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

    public func moveTo(_ position: LogicalPosition) {
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

    public func setMinSize(_ size: LogicalSize?) {
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

    public func setMaxSize(_ size: LogicalSize?) {
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

    public func requestFocus() {
        nsWindow.makeKeyAndOrderFront(nil)
    }

    public func scaleFactor() -> Float {
        Float(nsWindow.backingScaleFactor)
    }

    public func requestRedraw() {
        // Mark the content view as needing display
        nsWindow.contentView?.setNeedsDisplay(nsWindow.contentView!.bounds)

        // TODO: Also notify MacApplication to mark this window for redraw
        // This requires passing the application reference or using a callback
        // For now, we rely on NSView's setNeedsDisplay which triggers display events
    }

    public func setDecorated(_ decorated: Bool) throws {
        if decorated {
            // Add decorations
            var styleMask = nsWindow.styleMask
            styleMask.insert([.titled, .closable, .miniaturizable])
            nsWindow.styleMask = styleMask
        } else {
            // Remove decorations (borderless)
            nsWindow.styleMask = .borderless
        }
    }

    public func setAlwaysOnTop(_ alwaysOnTop: Bool) throws {
        if alwaysOnTop {
            nsWindow.level = .floating
        } else {
            nsWindow.level = .normal
        }
    }

    public func setTransparent(_ transparent: Bool) throws {
        nsWindow.isOpaque = !transparent
        nsWindow.backgroundColor = transparent ? .clear : .windowBackgroundColor
        nsWindow.hasShadow = !transparent
    }

    public func capabilities() -> WindowCapabilities {
        // macOS supports all Wave B features except client-side decorations
        return WindowCapabilities(
            supportsTransparency: true,
            supportsAlwaysOnTop: true,
            supportsDecorationToggle: true,
            supportsClientSideDecorations: false  // macOS uses system decorations
        )
    }

    public func currentMonitor() throws -> Monitor {
        // Get the screen this window is on
        guard let screen = nsWindow.screen else {
            throw LuminaError.monitorEnumerationFailed(reason: "Window has no associated screen")
        }

        // Enumerate all monitors and find the one matching this screen
        let monitors = try MacMonitor.enumerateMonitors()

        // Find monitor by matching screen properties
        for monitor in monitors {
            // Compare using screen frame position (approximate match due to floating point)
            let screenFrame = screen.frame
            let monitorPos = monitor.position
            let dx = abs(Float(screenFrame.origin.x) - monitorPos.x)
            let dy = abs(Float(screenFrame.origin.y) - monitorPos.y)

            if dx < 1.0 && dy < 1.0 {
                return monitor
            }
        }

        // If no exact match, return the first monitor
        if let first = monitors.first {
            return first
        }

        throw LuminaError.monitorEnumerationFailed(reason: "No monitors found")
    }

    public func cursor() -> any LuminaCursor {
        return MacCursor()
    }
}

// MARK: - MacCursor Implementation

/// macOS implementation of LuminaCursor using NSCursor
@MainActor
private struct MacCursor: LuminaCursor {
    func set(_ cursor: SystemCursor) {
        let nsCursor: NSCursor = switch cursor {
        case .arrow:
            .arrow
        case .ibeam:
            .iBeam
        case .crosshair:
            .crosshair
        case .hand:
            .pointingHand
        case .resizeNS:
            .resizeUpDown
        case .resizeEW:
            .resizeLeftRight
        case .resizeNESW:
            // macOS doesn't have a built-in diagonal resize cursor
            // Fall back to arrow for now
            .arrow
        case .resizeNWSE:
            // macOS doesn't have a built-in diagonal resize cursor
            // Fall back to arrow for now
            .arrow
        }
        nsCursor.set()
    }

    func hide() {
        NSCursor.hide()
    }

    func show() {
        NSCursor.unhide()
    }
}

extension MacCursor: @unchecked Sendable {}

// MARK: - Sendable Conformance

// MacWindow is @MainActor isolated, so it's safe to conform to Sendable
// NSWindow is a reference type, but all access is isolated to the main actor
extension MacWindow: @unchecked Sendable {}

#endif
