#if os(macOS)
import AppKit
import Foundation

/// macOS implementation of clipboard operations using NSPasteboard.
///
/// This implementation provides text clipboard operations via NSPasteboard.
/// All operations must be performed on the main thread as required by AppKit.
@MainActor
internal struct MacClipboard {
    /// Last observed change count for tracking clipboard changes
    private static var lastChangeCount: Int = 0

    /// Read UTF-8 text from the system clipboard.
    ///
    /// Returns the current clipboard text content if available, or nil if the
    /// clipboard is empty or contains non-text data.
    ///
    /// - Returns: The clipboard text content, or nil if unavailable
    /// - Throws: LuminaError.clipboardAccessDenied or LuminaError.clipboardReadFailed
    static func readText() throws -> String? {
        let pasteboard = NSPasteboard.general

        // Update change count tracking
        lastChangeCount = pasteboard.changeCount

        // Try to read string from clipboard
        guard let text = pasteboard.string(forType: .string) else {
            return nil
        }

        return text
    }

    /// Write UTF-8 text to the system clipboard.
    ///
    /// Replaces the current clipboard content with the provided text.
    ///
    /// - Parameter text: The UTF-8 text to write to the clipboard
    /// - Throws: LuminaError.clipboardAccessDenied or LuminaError.clipboardWriteFailed
    static func writeText(_ text: String) throws {
        let pasteboard = NSPasteboard.general

        // Clear current contents
        pasteboard.clearContents()

        // Write new text content
        let success = pasteboard.setString(text, forType: .string)

        // Update change count tracking
        lastChangeCount = pasteboard.changeCount

        if !success {
            throw LuminaError.clipboardWriteFailed(reason: "Failed to write text to NSPasteboard")
        }
    }

    /// Check if the clipboard content has changed since the last access.
    ///
    /// Returns true if the clipboard has been modified by this application or
    /// another application since the last call to readText() or writeText().
    ///
    /// - Returns: true if clipboard has changed, false otherwise
    static func hasChanged() -> Bool {
        let currentCount = NSPasteboard.general.changeCount
        return currentCount != lastChangeCount
    }

    /// Query clipboard capabilities for macOS.
    ///
    /// Returns ClipboardCapabilities struct describing which clipboard data types
    /// are supported on macOS.
    ///
    /// - Returns: ClipboardCapabilities struct with feature support flags
    static func capabilities() -> ClipboardCapabilities {
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,  // Future feature
            supportsHTML: false     // Future feature
        )
    }
}

#endif
