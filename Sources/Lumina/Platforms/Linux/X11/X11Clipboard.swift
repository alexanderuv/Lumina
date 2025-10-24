#if os(Linux)
import CXCBLinux
import Foundation

/// X11 clipboard implementation using the CLIPBOARD selection protocol.
///
/// This module provides clipboard text read/write functionality for X11 using
/// the CLIPBOARD selection (modern clipboard, different from PRIMARY selection
/// used for middle-click paste). It handles:
/// - Text write via xcb_set_selection_owner (claiming ownership)
/// - Text read via xcb_convert_selection (requesting data from owner)
/// - SelectionNotify event handling for read completion
/// - SelectionRequest event handling for serving data to other applications
/// - UTF-8 text encoding/decoding
/// - Synchronous API with internal event pumping and timeout
///
/// The X11 clipboard is based on a selection protocol where:
/// 1. To write: Application claims ownership of CLIPBOARD selection
/// 2. To read: Application requests conversion of CLIPBOARD to UTF8_STRING
/// 3. X server delivers SelectionNotify event with data transfer details
/// 4. Application retrieves property containing clipboard data
///
/// This implementation uses a 1-second timeout for clipboard reads to prevent
/// hanging if the selection owner doesn't respond.
///
/// Example usage:
/// ```swift
/// // Write text to clipboard
/// try X11Clipboard.writeText("Hello, clipboard!", connection: conn, window: window, atoms: atoms)
///
/// // Read text from clipboard
/// if let text = try X11Clipboard.readText(connection: conn, window: window, atoms: atoms) {
///     print("Clipboard: \(text)")
/// }
/// ```
@MainActor
public struct X11Clipboard {
    /// Temporary property atom for clipboard data transfer.
    ///
    /// When requesting clipboard data, we ask the selection owner to write
    /// the data to this property on our window. The name is arbitrary but
    /// should be unique to avoid conflicts.
    private static let CLIPBOARD_PROPERTY_NAME = "LUMINA_CLIPBOARD"

    // MARK: - Read Text

    /// Read UTF-8 text from the X11 CLIPBOARD selection.
    ///
    /// This function performs a synchronous clipboard read with internal event
    /// pumping and a 1.0 second timeout. The read process:
    /// 1. Intern CLIPBOARD_PROPERTY atom for data transfer
    /// 2. Send xcb_convert_selection to request UTF8_STRING from CLIPBOARD owner
    /// 3. Pump X events waiting for SelectionNotify (timeout 1.0s)
    /// 4. Extract data from property and decode as UTF-8
    /// 5. Delete property to clean up
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - window: A window owned by this application (used for property transfer)
    ///   - atoms: Cached X11 atoms (must include CLIPBOARD and UTF8_STRING)
    /// - Returns: Clipboard text content, or nil if clipboard is empty or contains non-text
    /// - Throws: LuminaError.clipboardReadFailed on timeout or protocol error
    ///
    /// Example:
    /// ```swift
    /// do {
    ///     if let text = try X11Clipboard.readText(connection: conn, window: window, atoms: atoms) {
    ///         print("Clipboard contains: \(text)")
    ///     } else {
    ///         print("Clipboard is empty")
    ///     }
    /// } catch {
    ///     print("Failed to read clipboard: \(error)")
    /// }
    /// ```
    public static func readText(
        connection: OpaquePointer,
        window: xcb_window_t,
        atoms: X11Atoms
    ) throws -> String? {
        // Intern property atom for data transfer
        let propCookie = xcb_intern_atom(
            connection,
            0,  // only_if_exists = false
            UInt16(CLIPBOARD_PROPERTY_NAME.utf8.count),
            CLIPBOARD_PROPERTY_NAME
        )
        guard let propReply = xcb_intern_atom_reply(connection, propCookie, nil) else {
            throw LuminaError.clipboardReadFailed(reason: "Failed to intern clipboard property atom")
        }
        let propertyAtom = propReply.pointee.atom
        free(propReply)

        // Request clipboard data: convert CLIPBOARD selection to UTF8_STRING on our property
        xcb_convert_selection(
            connection,
            window,                     // requestor window
            atoms.CLIPBOARD,            // selection (CLIPBOARD)
            atoms.UTF8_STRING,          // target format (UTF8_STRING)
            propertyAtom,               // property to write to
            UInt32(XCB_CURRENT_TIME)    // timestamp
        )
        _ = xcb_flush_shim(connection)

        // Wait for SelectionNotify event (with 1.0s timeout)
        let startTime = Date()
        let timeout: TimeInterval = 1.0

        while Date().timeIntervalSince(startTime) < timeout {
            // Poll for events (non-blocking)
            guard let event = xcb_poll_for_event(connection) else {
                // No events available, sleep briefly and retry
                usleep(10_000)  // 10ms
                continue
            }
            defer { free(event) }

            let responseType = xcb_event_response_type_shim(event) & 0x7f

            if Int32(responseType) == XCB_SELECTION_NOTIFY {
                let selectionEvent = event.withMemoryRebound(to: xcb_selection_notify_event_t.self, capacity: 1) { $0.pointee }

                // Check if selection conversion succeeded
                guard selectionEvent.property != XCB_ATOM_NONE.rawValue else {
                    // Selection conversion failed (clipboard empty or unavailable)
                    return nil
                }

                // Read property containing clipboard data
                let getPropCookie = xcb_get_property(
                    connection,
                    1,                      // delete property after reading
                    window,
                    propertyAtom,
                    atoms.UTF8_STRING,      // expected type
                    0,                      // offset
                    1024 * 1024             // max length (1MB should be enough for text)
                )

                var error: UnsafeMutablePointer<xcb_generic_error_t>?
                guard let propReply = xcb_get_property_reply(connection, getPropCookie, &error) else {
                    if let error = error {
                        let errorCode = Int(error.pointee.error_code)
                        free(error)
                        throw LuminaError.clipboardReadFailed(reason: "Failed to get clipboard property (error code: \(errorCode))")
                    }
                    throw LuminaError.clipboardReadFailed(reason: "Failed to get clipboard property")
                }
                defer { free(propReply) }

                // Extract data from property
                let length = Int(xcb_get_property_value_length(propReply))
                guard length > 0 else {
                    return nil  // Empty clipboard
                }

                guard let valuePtr = xcb_get_property_value(propReply) else {
                    return nil
                }

                // Convert to Swift String (UTF-8)
                let data = Data(bytes: valuePtr, count: length)
                return String(data: data, encoding: .utf8)
            }
        }

        // Timeout: no SelectionNotify received
        throw LuminaError.clipboardReadFailed(reason: "Clipboard read timeout (1.0s)")
    }

    // MARK: - Write Text

    /// Write UTF-8 text to the X11 CLIPBOARD selection.
    ///
    /// This function claims ownership of the CLIPBOARD selection and stores the
    /// text locally. When other applications request clipboard data, the X server
    /// sends SelectionRequest events that must be handled by serving the stored text.
    ///
    /// The write process:
    /// 1. Store text in static storage (for serving to requestors)
    /// 2. Call xcb_set_selection_owner to claim CLIPBOARD ownership
    /// 3. Verify ownership was granted
    ///
    /// After writing, the application must handle SelectionRequest events in its
    /// event loop to serve clipboard data to other applications.
    ///
    /// - Parameters:
    ///   - text: UTF-8 text to write to clipboard
    ///   - connection: Active XCB connection
    ///   - window: A window owned by this application (becomes selection owner)
    ///   - atoms: Cached X11 atoms (must include CLIPBOARD and UTF8_STRING)
    /// - Throws: LuminaError.clipboardWriteFailed if ownership cannot be claimed
    ///
    /// Example:
    /// ```swift
    /// try X11Clipboard.writeText("Hello, world!", connection: conn, window: window, atoms: atoms)
    /// print("Text written to clipboard")
    /// ```
    public static func writeText(
        _ text: String,
        connection: OpaquePointer,
        window: xcb_window_t,
        atoms: X11Atoms
    ) throws {
        // Store text for serving to requestors (must persist until selection is lost)
        // Note: In a real implementation, this would be stored per-window or in application state
        // For now, we'll use a simple static storage approach
        ClipboardStorage.shared.storedText = text
        ClipboardStorage.shared.ownerWindow = window

        // Claim ownership of CLIPBOARD selection
        xcb_set_selection_owner(
            connection,
            window,
            atoms.CLIPBOARD,
            UInt32(XCB_CURRENT_TIME)
        )
        _ = xcb_flush_shim(connection)

        // Verify ownership was granted
        let ownerCookie = xcb_get_selection_owner(connection, atoms.CLIPBOARD)
        guard let ownerReply = xcb_get_selection_owner_reply(connection, ownerCookie, nil) else {
            throw LuminaError.clipboardWriteFailed(reason: "Failed to verify clipboard ownership")
        }
        defer { free(ownerReply) }

        let actualOwner = ownerReply.pointee.owner
        guard actualOwner == window else {
            throw LuminaError.clipboardWriteFailed(
                reason: "Failed to claim clipboard ownership (owner: \(actualOwner), expected: \(window))"
            )
        }
    }

    // MARK: - SelectionRequest Handling

    /// Handle SelectionRequest event (serve clipboard data to requestor).
    ///
    /// This function should be called from the event loop when a SelectionRequest
    /// event is received. It serves the stored clipboard data to the requesting
    /// application by writing to the specified property.
    ///
    /// The serving process:
    /// 1. Verify we own the requested selection (CLIPBOARD)
    /// 2. Check if requestor wants UTF8_STRING format
    /// 3. Write stored text to requestor's property
    /// 4. Send SelectionNotify to complete transfer
    ///
    /// - Parameters:
    ///   - event: SelectionRequest event from X server
    ///   - connection: Active XCB connection
    ///   - atoms: Cached X11 atoms
    ///
    /// Example:
    /// ```swift
    /// // In event loop:
    /// case XCB_SELECTION_REQUEST:
    ///     let selectionRequest = event.withMemoryRebound(to: xcb_selection_request_event_t.self, capacity: 1) { $0.pointee }
    ///     X11Clipboard.handleSelectionRequest(event, connection: conn, atoms: atoms)
    /// ```
    public static func handleSelectionRequest(
        _ event: UnsafeMutablePointer<xcb_generic_event_t>,
        connection: OpaquePointer,
        atoms: X11Atoms
    ) {
        let selectionRequest = event.withMemoryRebound(to: xcb_selection_request_event_t.self, capacity: 1) { $0.pointee }

        // Check if this is for CLIPBOARD selection
        guard selectionRequest.selection == atoms.CLIPBOARD else {
            // Not our selection, send failure notification
            sendSelectionNotify(
                connection: connection,
                requestor: selectionRequest.requestor,
                selection: selectionRequest.selection,
                target: selectionRequest.target,
                property: XCB_ATOM_NONE.rawValue,  // None indicates failure
                time: selectionRequest.time
            )
            return
        }

        // Check if we have stored text and are the owner
        guard let storedText = ClipboardStorage.shared.storedText,
              selectionRequest.owner == ClipboardStorage.shared.ownerWindow else {
            // We don't own the selection or have no data
            sendSelectionNotify(
                connection: connection,
                requestor: selectionRequest.requestor,
                selection: selectionRequest.selection,
                target: selectionRequest.target,
                property: XCB_ATOM_NONE.rawValue,
                time: selectionRequest.time
            )
            return
        }

        // Check if requestor wants UTF8_STRING
        guard selectionRequest.target == atoms.UTF8_STRING else {
            // Unsupported target format
            sendSelectionNotify(
                connection: connection,
                requestor: selectionRequest.requestor,
                selection: selectionRequest.selection,
                target: selectionRequest.target,
                property: XCB_ATOM_NONE.rawValue,
                time: selectionRequest.time
            )
            return
        }

        // Write clipboard text to requestor's property
        let utf8Data = Array(storedText.utf8)
        xcb_change_property(
            connection,
            UInt8(XCB_PROP_MODE_REPLACE.rawValue),
            selectionRequest.requestor,
            selectionRequest.property,
            atoms.UTF8_STRING,
            8,  // format: 8-bit data
            UInt32(utf8Data.count),
            utf8Data
        )

        // Send SelectionNotify to complete transfer
        sendSelectionNotify(
            connection: connection,
            requestor: selectionRequest.requestor,
            selection: selectionRequest.selection,
            target: selectionRequest.target,
            property: selectionRequest.property,
            time: selectionRequest.time
        )
    }

    /// Send SelectionNotify event to complete clipboard transfer.
    ///
    /// - Parameters:
    ///   - connection: Active XCB connection
    ///   - requestor: Window that requested clipboard data
    ///   - selection: Selection atom (CLIPBOARD)
    ///   - target: Target format atom (UTF8_STRING)
    ///   - property: Property atom where data was written (or XCB_ATOM_NONE on failure)
    ///   - time: Timestamp from SelectionRequest
    private static func sendSelectionNotify(
        connection: OpaquePointer,
        requestor: xcb_window_t,
        selection: xcb_atom_t,
        target: xcb_atom_t,
        property: xcb_atom_t,
        time: xcb_timestamp_t
    ) {
        // Build SelectionNotify event
        var notifyEvent = xcb_selection_notify_event_t()
        notifyEvent.response_type = UInt8(XCB_SELECTION_NOTIFY)
        notifyEvent.time = time
        notifyEvent.requestor = requestor
        notifyEvent.selection = selection
        notifyEvent.target = target
        notifyEvent.property = property

        // Send event to requestor
        withUnsafeBytes(of: &notifyEvent) { bytes in
            let eventPtr = bytes.baseAddress!.assumingMemoryBound(to: CChar.self)
            xcb_send_event(
                connection,
                0,  // propagate = false
                requestor,
                0,  // event_mask = 0 (no mask)
                eventPtr
            )
        }

        _ = xcb_flush_shim(connection)
    }
}

// MARK: - Clipboard Storage

/// Thread-safe storage for clipboard text.
///
/// This stores the clipboard text that we've written, so we can serve it
/// to other applications when they request it via SelectionRequest events.
///
/// In a production implementation, this should be integrated into application
/// state and handle multiple windows properly.
private final class ClipboardStorage: @unchecked Sendable {
    static let shared = ClipboardStorage()

    private let lock = NSLock()
    private var _storedText: String?
    private var _ownerWindow: xcb_window_t = 0

    var storedText: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _storedText
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _storedText = newValue
        }
    }

    var ownerWindow: xcb_window_t {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _ownerWindow
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _ownerWindow = newValue
        }
    }

    private init() {}
}

// MARK: - Public Clipboard API (Linux)

/// Internal namespace for Linux-specific clipboard implementations.
///
/// This struct is not meant to be instantiated directly. It provides
/// static methods that are called by the public Clipboard API when
/// running on Linux.
@MainActor
struct LinuxClipboard {
    private init() {}

    static func readText() throws -> String? {
        // This function should be called with application's XCB connection
        // For now, we'll throw an error indicating the app must be initialized
        throw LuminaError.clipboardReadFailed(
            reason: "Clipboard access requires initialized X11Application. Use through event loop context."
        )
    }

    static func writeText(_ text: String) throws {
        // This function should be called with application's XCB connection
        // For now, we'll throw an error indicating the app must be initialized
        throw LuminaError.clipboardWriteFailed(
            reason: "Clipboard access requires initialized X11Application. Use through event loop context."
        )
    }

    static func hasChanged() -> Bool {
        // Change tracking not implemented yet
        return false
    }

    static func capabilities() -> ClipboardCapabilities {
        return ClipboardCapabilities(
            supportsText: true,
            supportsImages: false,  // Not implemented in M1
            supportsHTML: false     // Not implemented in M1
        )
    }
}

#endif
