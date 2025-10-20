/// Cross-platform clipboard access for text and other data types.
///
/// The Clipboard API provides a unified interface for clipboard operations across
/// all supported platforms. All operations must be performed on the main thread
/// (@MainActor) as required by platform clipboard APIs.
///
/// The current implementation supports UTF-8 text only. Future versions will add
/// support for images, HTML, and custom data formats.

/// Clipboard operations for reading and writing system clipboard data.
///
/// The Clipboard struct provides static methods for clipboard access. All methods
/// must be called from the main thread and may throw errors if clipboard access
/// fails or is denied by the system.
///
/// Example:
/// ```swift
/// // Write text to clipboard
/// try Clipboard.writeText("Hello, clipboard!")
///
/// // Read text from clipboard
/// if let text = try Clipboard.readText() {
///     print("Clipboard contains: \(text)")
/// } else {
///     print("Clipboard is empty or contains non-text data")
/// }
///
/// // Check if clipboard has changed since last access
/// if Clipboard.hasChanged() {
///     print("Clipboard content has been modified")
/// }
/// ```
@MainActor
public struct Clipboard {
    // Prevent instantiation - this is a namespace for static methods
    private init() {}

    /// Read UTF-8 text from the system clipboard.
    ///
    /// Returns the current clipboard text content if available, or nil if the
    /// clipboard is empty or contains non-text data (images, files, etc.).
    ///
    /// This operation may fail if:
    /// - Clipboard access is denied by the system
    /// - The clipboard is locked by another application
    /// - A platform-specific error occurs
    ///
    /// - Returns: The clipboard text content, or nil if unavailable
    /// - Throws: LuminaError.clipboardAccessDenied or LuminaError.clipboardReadFailed
    ///
    /// Example:
    /// ```swift
    /// do {
    ///     if let text = try Clipboard.readText() {
    ///         print("Clipboard: \(text)")
    ///     } else {
    ///         print("No text on clipboard")
    ///     }
    /// } catch {
    ///     print("Failed to read clipboard: \(error)")
    /// }
    /// ```
    public static func readText() throws -> String? {
        #if os(macOS)
        return try MacClipboard.readText()
        #elseif os(Windows)
        return try WinClipboard.readText()
        #elseif os(Linux)
        return try LinuxClipboard.readText()
        #else
        throw LuminaError.platformNotSupported(operation: "Clipboard read")
        #endif
    }

    /// Write UTF-8 text to the system clipboard.
    ///
    /// Replaces the current clipboard content with the provided text. The text
    /// becomes available to other applications immediately.
    ///
    /// This operation may fail if:
    /// - Clipboard access is denied by the system
    /// - The clipboard is locked by another application
    /// - A platform-specific error occurs
    ///
    /// - Parameter text: The UTF-8 text to write to the clipboard
    /// - Throws: LuminaError.clipboardAccessDenied or LuminaError.clipboardWriteFailed
    ///
    /// Example:
    /// ```swift
    /// do {
    ///     try Clipboard.writeText("Hello, world!")
    ///     print("Text written to clipboard")
    /// } catch {
    ///     print("Failed to write clipboard: \(error)")
    /// }
    /// ```
    public static func writeText(_ text: String) throws {
        #if os(macOS)
        try MacClipboard.writeText(text)
        #elseif os(Windows)
        try WinClipboard.writeText(text)
        #elseif os(Linux)
        try LinuxClipboard.writeText(text)
        #else
        throw LuminaError.platformNotSupported(operation: "Clipboard write")
        #endif
    }

    /// Check if the clipboard content has changed since the last access.
    ///
    /// Returns true if the clipboard has been modified by this application or
    /// another application since the last call to `readText()` or `writeText()`.
    ///
    /// This is useful for polling clipboard changes or implementing clipboard
    /// history features.
    ///
    /// Note: This function does not throw and always returns false on platforms
    /// where change tracking is unavailable.
    ///
    /// - Returns: true if clipboard has changed, false otherwise
    ///
    /// Example:
    /// ```swift
    /// // Poll for clipboard changes
    /// var lastText: String? = try Clipboard.readText()
    ///
    /// Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    ///     if Clipboard.hasChanged() {
    ///         if let newText = try? Clipboard.readText() {
    ///             print("Clipboard changed: \(newText ?? "empty")")
    ///             lastText = newText
    ///         }
    ///     }
    /// }
    /// ```
    public static func hasChanged() -> Bool {
        #if os(macOS)
        return MacClipboard.hasChanged()
        #elseif os(Windows)
        return WinClipboard.hasChanged()
        #elseif os(Linux)
        return LinuxClipboard.hasChanged()
        #else
        return false
        #endif
    }

    /// Query clipboard capabilities for the current platform.
    ///
    /// Returns a ClipboardCapabilities struct describing which clipboard data types
    /// are supported on this platform. Use this to determine whether to show UI
    /// for advanced clipboard features.
    ///
    /// - Returns: ClipboardCapabilities struct with feature support flags
    ///
    /// Example:
    /// ```swift
    /// let caps = Clipboard.capabilities()
    /// if caps.supportsText {
    ///     // Show text paste button
    /// }
    /// if caps.supportsImages {
    ///     // Show image paste button (future feature)
    /// }
    /// ```
    public static func capabilities() -> ClipboardCapabilities {
        #if os(macOS)
        return MacClipboard.capabilities()
        #elseif os(Windows)
        return WinClipboard.capabilities()
        #elseif os(Linux)
        return LinuxClipboard.capabilities()
        #else
        return ClipboardCapabilities(
            supportsText: false,
            supportsImages: false,
            supportsHTML: false
        )
        #endif
    }
}
