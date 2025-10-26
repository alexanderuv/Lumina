#if os(Windows)

import WinSDK
import Foundation

/// Windows clipboard implementation using Win32 API.
///
/// This implementation provides text clipboard support via OpenClipboard/GetClipboardData/SetClipboardData.
/// Images and HTML support will be added in future milestones.
internal struct WinClipboard {
    /// Read text from the clipboard.
    ///
    /// - Returns: The text content of the clipboard
    /// - Throws: LuminaError if clipboard access fails or no text is available
    static func readText() throws -> String {
        // Open the clipboard
        guard OpenClipboard(nil) else {
            throw LuminaError.clipboardReadFailed(reason: "Failed to open clipboard")
        }
        defer { CloseClipboard() }

        // Get clipboard data in Unicode format
        guard let hData = GetClipboardData(UINT(CF_UNICODETEXT)) else {
            throw LuminaError.clipboardReadFailed(reason: "No text data in clipboard")
        }

        // Lock the global memory object
        guard let pData = GlobalLock(hData) else {
            throw LuminaError.clipboardReadFailed(reason: "Failed to lock clipboard data")
        }
        defer { GlobalUnlock(hData) }

        // Convert to Swift String from wide char pointer
        let wcharPtr = pData.bindMemory(to: WCHAR.self, capacity: 1)
        return String(decodingCString: wcharPtr, as: UTF16.self)
    }

    /// Write text to the clipboard.
    ///
    /// - Parameter text: The text to write to the clipboard
    /// - Throws: LuminaError if clipboard access fails
    static func writeText(_ text: String) throws {
        // Open the clipboard
        guard OpenClipboard(nil) else {
            throw LuminaError.clipboardWriteFailed(reason: "Failed to open clipboard")
        }
        defer { CloseClipboard() }

        // Empty the clipboard
        guard EmptyClipboard() else {
            throw LuminaError.clipboardWriteFailed(reason: "Failed to empty clipboard")
        }

        // Convert string to UTF-16 (wide char)
        let utf16Data = Array(text.utf16) + [0] // Null-terminated
        let byteSize = utf16Data.count * MemoryLayout<WCHAR>.size

        // Allocate global memory
        guard let hGlobal = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(byteSize)) else {
            throw LuminaError.clipboardWriteFailed(reason: "Failed to allocate memory")
        }

        // Lock and copy data
        guard let pData = GlobalLock(hGlobal) else {
            GlobalFree(hGlobal)
            throw LuminaError.clipboardWriteFailed(reason: "Failed to lock memory")
        }

        utf16Data.withUnsafeBytes { buffer in
            pData.copyMemory(from: buffer.baseAddress!, byteCount: byteSize)
        }

        GlobalUnlock(hGlobal)

        // Set clipboard data
        guard SetClipboardData(UINT(CF_UNICODETEXT), hGlobal) != nil else {
            GlobalFree(hGlobal)
            throw LuminaError.clipboardWriteFailed(reason: "Failed to set clipboard data")
        }
    }

    /// Check if clipboard content has changed since last check.
    ///
    /// - Returns: Always true for now (change detection not implemented)
    static func hasChanged() -> Bool {
        // Windows doesn't provide a simple API for clipboard change detection
        // without using clipboard format listeners. For now, return true.
        // TODO: Implement proper change detection using AddClipboardFormatListener
        return true
    }

    /// Query clipboard capabilities.
    ///
    /// - Returns: ClipboardCapabilities for Windows
    static func capabilities() -> ClipboardCapabilities {
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,  // Not implemented yet
            supportsHTML: false     // Not implemented yet
        )
    }
}

#endif
