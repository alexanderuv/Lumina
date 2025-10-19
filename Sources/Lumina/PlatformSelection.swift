/// Platform-specific type selection.
///
/// This file provides type aliases that automatically select the correct
/// platform-specific implementation based on the compilation target.

#if os(Windows)
/// The platform-specific application type for the current platform.
///
/// On Windows, this is WinApplication which handles:
/// - DPI awareness (Per-Monitor V2 or V1)
/// - COM initialization
/// - Win32 message pump
///
/// Users should typealias this to create their application:
/// ```swift
/// @main
/// struct MyApp: LuminaApp {
///     private var platform: PlatformBackend
///
///     public init() throws {
///         self.platform = try PlatformBackend()
///     }
///     // ... rest of implementation
/// }
/// ```
public typealias PlatformBackend = WinApplication

#elseif os(macOS)
/// The platform-specific application type for the current platform.
///
/// On macOS, this is MacApplication which handles:
/// - NSApplication initialization
/// - Activation policy
/// - Event loop integration with CFRunLoop
public typealias PlatformBackend = MacApplication

#else
#error("Unsupported platform")
#endif
