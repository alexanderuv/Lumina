import Foundation

/// Unique identifier for a window.
///
/// WindowID provides a type-safe way to reference windows and associate
/// events with specific window instances. Each window created by Lumina
/// has a unique identifier that persists for the lifetime of the window.
///
/// WindowID is used throughout the event system to track which window
/// generated or should handle a specific event.
///
/// Example:
/// ```swift
/// let window1 = try Window.create(title: "Window 1", size: LogicalSize(width: 800, height: 600)).get()
/// let window2 = try Window.create(title: "Window 2", size: LogicalSize(width: 640, height: 480)).get()
///
/// // Each window has a unique ID
/// assert(window1.id != window2.id)
///
/// // Events contain the window ID they're associated with
/// if case .window(.resized(let windowID, let size)) = event {
///     if windowID == window1.id {
///         print("Window 1 was resized to \(size)")
///     }
/// }
/// ```
public struct WindowID: Identifiable, Sendable, Hashable {
    /// The unique identifier value
    public let id: UUID

    /// Create a new unique window identifier.
    ///
    /// Each call to this initializer generates a new, globally unique ID.
    /// This is typically called internally by the window creation system.
    public init() {
        self.id = UUID()
    }

    /// Create a window identifier from an existing UUID.
    ///
    /// This initializer is primarily used for testing or when deserializing
    /// window identifiers from persistent storage.
    ///
    /// - Parameter id: The UUID to use as the identifier
    public init(id: UUID) {
        self.id = id
    }
}

extension WindowID: CustomStringConvertible {
    public var description: String {
        "WindowID(\(id.uuidString.prefix(8))...)"
    }
}
