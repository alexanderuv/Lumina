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

        // Find CWaylandClient directory
        let packageURL = URL(fileURLWithPath: context.package.directoryURL.path())
        let outputURL = packageURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("CInterop")
            .appendingPathComponent("CWaylandClient")
        let includeURL = outputURL.appendingPathComponent("include")

        print("Generating Wayland protocol bindings...")
        print("Output directory: \(outputURL.path())")

        // Find wayland-scanner
        let waylandScanner = try context.tool(named: "wayland-scanner")

        for (name, xmlPath) in protocols {
            print("  - \(name)")

            let headerPath = includeURL.appendingPathComponent("\(name)-client-protocol.h")
            let codePath = outputURL.appendingPathComponent("\(name)-client-protocol.c")

            // Generate header
            let headerProcess = Process()
            headerProcess.executableURL = URL(fileURLWithPath: waylandScanner.url.path())
            headerProcess.arguments = ["client-header", xmlPath, headerPath.path()]
            try headerProcess.run()
            headerProcess.waitUntilExit()

            if headerProcess.terminationStatus != 0 {
                throw PluginError.headerGenerationFailed(name)
            }

            // Generate code
            let codeProcess = Process()
            codeProcess.executableURL = URL(fileURLWithPath: waylandScanner.url.path())
            codeProcess.arguments = ["private-code", xmlPath, codePath.path()]
            try codeProcess.run()
            codeProcess.waitUntilExit()

            if codeProcess.terminationStatus != 0 {
                throw PluginError.codeGenerationFailed(name)
            }
        }

        print("Done! Protocol bindings generated successfully.")
    }
}

enum PluginError: Error, CustomStringConvertible {
    case headerGenerationFailed(String)
    case codeGenerationFailed(String)

    var description: String {
        switch self {
        case .headerGenerationFailed(let name):
            return "Failed to generate header for \(name)"
        case .codeGenerationFailed(let name):
            return "Failed to generate code for \(name)"
        }
    }
}
