import PackagePlugin
import Foundation

@main
struct WaylandProtocolGenerator: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let protocolsPath = "/usr/share/wayland-protocols"
        let protocols: [(name: String, path: String)] = [
            ("xdg-shell", "\(protocolsPath)/stable/xdg-shell/xdg-shell.xml"),
            ("viewporter", "\(protocolsPath)/stable/viewporter/viewporter.xml"),
            ("pointer-constraints-unstable-v1", "\(protocolsPath)/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml"),
            ("relative-pointer-unstable-v1", "\(protocolsPath)/unstable/relative-pointer/relative-pointer-unstable-v1.xml"),
            ("xdg-decoration-unstable-v1", "\(protocolsPath)/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml")
        ]

        // Output to source directory for in-tree generation
        let packageURL = context.package.directoryURL
        let outputURL = packageURL
            .appending(path: "Sources/CInterop/CWaylandClient")
        let includeURL = outputURL.appending(path: "include")

        print("Generating Wayland protocol bindings...")
        print("Output directory: \(outputURL.path())")

        // Find system wayland-scanner
        let waylandScannerURL = try findWaylandScanner()

        for (name, xmlPath) in protocols {
            print("  - \(name)")

            let headerPath = includeURL.appending(path: "\(name)-client-protocol.h")
            let codePath = outputURL.appending(path: "\(name)-client-protocol.c")

            // Generate header
            let headerProcess = Process()
            headerProcess.executableURL = waylandScannerURL
            headerProcess.arguments = ["client-header", xmlPath, headerPath.path()]
            try headerProcess.run()
            headerProcess.waitUntilExit()

            if headerProcess.terminationStatus != 0 {
                throw PluginError.headerGenerationFailed(name)
            }

            // Generate code
            let codeProcess = Process()
            codeProcess.executableURL = waylandScannerURL
            codeProcess.arguments = ["private-code", xmlPath, codePath.path()]
            try codeProcess.run()
            codeProcess.waitUntilExit()

            if codeProcess.terminationStatus != 0 {
                throw PluginError.codeGenerationFailed(name)
            }
        }

        print("Done! Protocol bindings generated successfully.")
    }

    private func findWaylandScanner() throws -> URL {
        let possiblePaths = [
            "/usr/bin/wayland-scanner",
            "/usr/local/bin/wayland-scanner",
            "/opt/homebrew/bin/wayland-scanner"
        ]

        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path()) {
                return url
            }
        }

        throw PluginError.waylandScannerNotFound
    }
}

enum PluginError: Error, CustomStringConvertible {
    case waylandScannerNotFound
    case headerGenerationFailed(String)
    case codeGenerationFailed(String)

    var description: String {
        switch self {
        case .waylandScannerNotFound:
            return """
            Error: wayland-scanner not found in standard locations
            Please install wayland-protocols package:
              Ubuntu/Debian: sudo apt install wayland-protocols
              Fedora: sudo dnf install wayland-protocols-devel
            """
        case .headerGenerationFailed(let name):
            return "Failed to generate header for \(name)"
        case .codeGenerationFailed(let name):
            return "Failed to generate code for \(name)"
        }
    }
}
