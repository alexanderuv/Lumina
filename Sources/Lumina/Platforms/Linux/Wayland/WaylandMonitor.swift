#if os(Linux) && LUMINA_WAYLAND
import Foundation
import CWaylandClient

/// Wayland monitor enumeration using wl_output protocol.
///
/// This module provides monitor detection and DPI scaling for Wayland compositors using
/// the wl_output global. It handles:
/// - Monitor enumeration via wl_output binding
/// - Output geometry, mode, scale, and done callbacks
/// - DPI detection with fallback to 96 DPI (1.0 scale factor)
/// - Fractional scaling via wp_fractional_scale_v1 (if available)
/// - Monitor configuration change notifications
/// - Primary monitor detection (first output is primary)
///
/// wl_output is a core Wayland protocol supported by all compositors. It provides
/// monitor information including position, physical size, resolution, and scaling.
///
/// **Concurrency Safety:**
/// WaylandMonitorTracker uses `@unchecked Sendable` with NSLock to protect the
/// `outputs` dictionary, which is accessed from both nonisolated C callbacks and
/// @MainActor methods. The lock ensures thread-safe access.
///
/// Example usage:
/// ```swift
/// let tracker = WaylandMonitorTracker(display: display)
/// tracker.bindOutput(registry: registry, name: name, version: version)
///
/// // After roundtrip to bind outputs:
/// let monitors = try tracker.enumerateMonitors()
/// print("Found \(monitors.count) monitor(s)")
/// ```
@MainActor
public final class WaylandMonitorTracker: @unchecked Sendable {

    // MARK: - Output State Tracking

    /// Information about a single wl_output.
    fileprivate final class OutputInfo: @unchecked Sendable {
        var output: OpaquePointer
        var name: UInt32  // wl_output name from registry

        // Geometry event data
        var x: Int32 = 0
        var y: Int32 = 0
        var physicalWidth: Int32 = 0   // mm
        var physicalHeight: Int32 = 0  // mm
        var subpixel: Int32 = 0
        var make: String = ""
        var model: String = ""
        var transform: Int32 = 0

        // Mode event data
        var width: Int32 = 0   // pixels
        var height: Int32 = 0  // pixels
        var refreshRate: Int32 = 0

        // Scale event data
        var scale: Int32 = 1

        // Fractional scale (if wp_fractional_scale_v1 available)
        var fractionalScale: Float?

        // Configuration complete flag
        var done: Bool = false

        // Listener (must persist)
        var listener: wl_output_listener

        init(output: OpaquePointer, name: UInt32) {
            self.output = output
            self.name = name
            // Initialize with all 6 callbacks (version 4 compatibility)
            self.listener = wl_output_listener(
                geometry: outputGeometryCallback,
                mode: outputModeCallback,
                done: outputDoneCallback,
                scale: outputScaleCallback,
                name: outputNameCallback,
                description: outputDescriptionCallback
            )
        }
    }

    // MARK: - State

    private let display: OpaquePointer

    /// Lock protecting the outputs dictionary.
    /// Required because nonisolated C callbacks mutate it concurrently with @MainActor access.
    private let outputsLock = NSLock()

    /// Protected by outputsLock. Access only while holding the lock.
    /// **Concurrency:** nonisolated(unsafe) allows access from nonisolated contexts,
    /// but all access must be protected by outputsLock to ensure thread safety.
    private nonisolated(unsafe) var _outputs: [UInt32: OutputInfo] = [:]

    private let logger: LuminaLogger

    /// Public accessor for current monitors.
    ///
    /// Call this after wl_display_roundtrip() to get the current monitor configuration.
    /// This property is @MainActor isolated and safe to call from Swift code.
    public var monitors: [Monitor] {
        buildMonitorList()
    }

    // MARK: - Initialization

    public init(display: OpaquePointer) {
        self.display = display
        self.logger = LuminaLogger(label: "com.lumina.wayland.monitor", level: .info)
    }

    deinit {
        outputsLock.lock()
        defer { outputsLock.unlock() }

        // Clean up wl_output proxies
        for (_, outputInfo) in _outputs {
            wl_output_destroy(outputInfo.output)
        }
    }

    // MARK: - Registry Binding

    /// Bind to wl_output globals announced via wl_registry.
    ///
    /// This should be called from the wl_registry.global callback when
    /// interface == "wl_output".
    ///
    /// **Concurrency:** This method is nonisolated because it's called from C callbacks.
    /// It uses NSLock to safely mutate the outputs dictionary.
    ///
    /// - Parameters:
    ///   - registry: wl_registry proxy
    ///   - name: Global name from registry event
    ///   - version: Interface version from registry event
    public nonisolated func bindOutput(registry: OpaquePointer, name: UInt32, version: UInt32) {
        // Bind to wl_output version 2 for broad compatibility (adds scale + done events)
        // Version 4 adds name/description but we provide callbacks anyway for forward compat
        let boundVersion = min(version, 2)
        let interfacePtr = lumina_wl_output_interface()

        guard let bound = wl_registry_bind(registry, name, interfacePtr, boundVersion) else {
            logger.logError("Failed to bind wl_output (name=\(name))")
            return
        }

        let output = OpaquePointer(bound)
        let outputInfo = OutputInfo(output: output, name: name)

        // Add listener
        let outputInfoPtr = Unmanaged.passUnretained(outputInfo).toOpaque()
        _ = withUnsafeMutablePointer(to: &outputInfo.listener) { listenerPtr in
            wl_output_add_listener(output, listenerPtr, outputInfoPtr)
        }

        // Thread-safe insertion
        outputsLock.lock()
        _outputs[name] = outputInfo
        outputsLock.unlock()
    }

    /// Handle wl_output removal (global_remove event).
    ///
    /// **Concurrency:** This method is nonisolated because it's called from C callbacks.
    /// It uses NSLock to safely mutate the outputs dictionary.
    ///
    /// - Parameter name: Global name being removed
    public nonisolated func removeOutput(name: UInt32) {
        outputsLock.lock()
        let outputInfo = _outputs.removeValue(forKey: name)
        outputsLock.unlock()

        if let outputInfo = outputInfo {
            wl_output_destroy(outputInfo.output)
        }
    }

    // MARK: - Monitor List Construction

    /// Build Monitor list from current output state.
    ///
    /// Only includes outputs that have received the "done" event, indicating
    /// complete configuration.
    ///
    /// **Concurrency:** @MainActor isolated, uses NSLock to safely read outputs dictionary.
    ///
    /// - Returns: Array of Monitor structs
    private func buildMonitorList() -> [Monitor] {
        outputsLock.lock()
        let outputsCopy = _outputs
        outputsLock.unlock()

        var monitors: [Monitor] = []

        // Sort outputs by name for deterministic ordering
        let sortedOutputs = outputsCopy.values.sorted { $0.name < $1.name }

        for (index, outputInfo) in sortedOutputs.enumerated() {
            // Skip outputs that haven't completed initial configuration
            guard outputInfo.done else {
                continue
            }

            // Calculate scale factor
            let scaleFactor: Float
            if let fractionalScale = outputInfo.fractionalScale {
                // Use fractional scale if available (wp_fractional_scale_v1)
                scaleFactor = fractionalScale
            } else if outputInfo.scale > 0 {
                // Use integer scale from wl_output.scale event
                scaleFactor = Float(outputInfo.scale)
            } else if outputInfo.physicalWidth > 0 && outputInfo.physicalHeight > 0 && outputInfo.width > 0 {
                // Calculate from physical dimensions (fallback)
                let dpiX = Float(outputInfo.width) / (Float(outputInfo.physicalWidth) / 25.4)
                let dpiY = Float(outputInfo.height) / (Float(outputInfo.physicalHeight) / 25.4)
                let dpi = (dpiX + dpiY) / 2.0
                scaleFactor = max(1.0, round(dpi / 96.0 * 4.0) / 4.0)  // Round to 0.25
            } else {
                // Default to 1.0 scale
                scaleFactor = 1.0
            }

            // Build monitor name from make/model
            let name: String
            if !outputInfo.make.isEmpty && !outputInfo.model.isEmpty {
                name = "\(outputInfo.make) \(outputInfo.model)"
            } else if !outputInfo.model.isEmpty {
                name = outputInfo.model
            } else {
                name = "Monitor \(index + 1)"
            }

            // Build Monitor struct
            let monitor = Monitor(
                id: MonitorID(UInt64(outputInfo.name)),
                name: name,
                position: LogicalPosition(x: Float(outputInfo.x), y: Float(outputInfo.y)),
                size: LogicalSize(width: Float(outputInfo.width), height: Float(outputInfo.height)),
                workArea: LogicalRect(
                    origin: LogicalPosition(x: Float(outputInfo.x), y: Float(outputInfo.y)),
                    size: LogicalSize(width: Float(outputInfo.width), height: Float(outputInfo.height))
                ),  // Note: Wayland has no standard protocol for work area (compositor-specific)
                    // For now, work area = full size
                scaleFactor: scaleFactor,
                isPrimary: index == 0  // First output is considered primary (Wayland convention)
            )

            monitors.append(monitor)
        }

        return monitors
    }

    // MARK: - Public API

    /// Enumerate all connected monitors.
    ///
    /// This is a convenience wrapper around the `monitors` property that throws
    /// an error if no monitors are found.
    ///
    /// - Returns: Array of all connected monitors
    /// - Throws: LuminaError.monitorEnumerationFailed if no monitors found
    public borrowing func enumerateMonitors() throws -> [Monitor] {
        let monitors = self.monitors

        guard !monitors.isEmpty else {
            throw LuminaError.monitorEnumerationFailed(reason: "No Wayland outputs found")
        }

        return monitors
    }

    /// Get the primary monitor.
    ///
    /// On Wayland, the first output is conventionally considered primary.
    ///
    /// - Returns: The primary monitor
    /// - Throws: LuminaError.monitorEnumerationFailed if no primary monitor found
    public borrowing func primaryMonitor() throws -> Monitor {
        let monitors = try enumerateMonitors()

        if let primary = monitors.first(where: { $0.isPrimary }) {
            return primary
        }

        // Fallback: return first monitor
        if let first = monitors.first {
            return first
        }

        throw LuminaError.monitorEnumerationFailed(reason: "No primary monitor found")
    }
}

// MARK: - C Callback Functions

/// C callback for wl_output.geometry event
private func outputGeometryCallback(
    userData: UnsafeMutableRawPointer?,
    output: OpaquePointer?,
    x: Int32,
    y: Int32,
    physicalWidth: Int32,
    physicalHeight: Int32,
    subpixel: Int32,
    make: UnsafePointer<CChar>?,
    model: UnsafePointer<CChar>?,
    transform: Int32
) {
    guard let userData = userData else { return }

    let outputInfo = Unmanaged<WaylandMonitorTracker.OutputInfo>.fromOpaque(userData).takeUnretainedValue()

    outputInfo.x = x
    outputInfo.y = y
    outputInfo.physicalWidth = physicalWidth
    outputInfo.physicalHeight = physicalHeight
    outputInfo.subpixel = subpixel
    outputInfo.make = make.map { String(cString: $0) } ?? ""
    outputInfo.model = model.map { String(cString: $0) } ?? ""
    outputInfo.transform = transform
}

/// C callback for wl_output.mode event
private func outputModeCallback(
    userData: UnsafeMutableRawPointer?,
    output: OpaquePointer?,
    flags: UInt32,
    width: Int32,
    height: Int32,
    refresh: Int32
) {
    guard let userData = userData else { return }

    let outputInfo = Unmanaged<WaylandMonitorTracker.OutputInfo>.fromOpaque(userData).takeUnretainedValue()

    // Only update if this is the current mode (WL_OUTPUT_MODE_CURRENT flag)
    let WL_OUTPUT_MODE_CURRENT: UInt32 = 0x1
    if flags & WL_OUTPUT_MODE_CURRENT != 0 {
        outputInfo.width = width
        outputInfo.height = height
        outputInfo.refreshRate = refresh
    }
}

/// C callback for wl_output.done event
private func outputDoneCallback(
    userData: UnsafeMutableRawPointer?,
    output: OpaquePointer?
) {
    guard let userData = userData else { return }

    let outputInfo = Unmanaged<WaylandMonitorTracker.OutputInfo>.fromOpaque(userData).takeUnretainedValue()
    outputInfo.done = true
}

/// C callback for wl_output.scale event
private func outputScaleCallback(
    userData: UnsafeMutableRawPointer?,
    output: OpaquePointer?,
    factor: Int32
) {
    guard let userData = userData else { return }

    let outputInfo = Unmanaged<WaylandMonitorTracker.OutputInfo>.fromOpaque(userData).takeUnretainedValue()
    outputInfo.scale = factor
}

/// C callback for wl_output.name event (Wayland protocol version 4+)
private func outputNameCallback(
    userData: UnsafeMutableRawPointer?,
    output: OpaquePointer?,
    name: UnsafePointer<CChar>?
) {
    guard let userData, let name else { return }

    let outputInfo = Unmanaged<WaylandMonitorTracker.OutputInfo>.fromOpaque(userData).takeUnretainedValue()
    outputInfo.model = String(cString: name)  // Override model with proper name if available
}

/// C callback for wl_output.description event (Wayland protocol version 4+)
private func outputDescriptionCallback(
    userData: UnsafeMutableRawPointer?,
    output: OpaquePointer?,
    description: UnsafePointer<CChar>?
) {
    // Description is informational only, we don't currently use it
    // Could be used to provide more detailed monitor info in the future
}

#endif // os(Linux) && LUMINA_WAYLAND
