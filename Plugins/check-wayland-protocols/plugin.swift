import PackagePlugin
import Foundation

@main
struct CheckWaylandProtocols: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only check for CWaylandClient target
        guard target.name == "CWaylandClient" else {
            return []
        }

        // Check if protocol files exist
        let packageURL = URL(fileURLWithPath: context.package.directoryURL.path())
        let waylandClientURL = packageURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("CInterop")
            .appendingPathComponent("CWaylandClient")

        let requiredFiles = [
            "xdg-shell-client-protocol.c",
            "viewporter-client-protocol.c",
            "pointer-constraints-unstable-v1-client-protocol.c",
            "relative-pointer-unstable-v1-client-protocol.c",
            "xdg-decoration-unstable-v1-client-protocol.c"
        ]

        let missingFiles = requiredFiles.filter { filename in
            let filePath = waylandClientURL.appendingPathComponent(filename)
            return !FileManager.default.fileExists(atPath: filePath.path())
        }

        if !missingFiles.isEmpty {
            let warningMessage = """
            Wayland protocol bindings not found. If you want to use LUMINA_WAYLAND, run:

                swift package plugin generate-wayland-protocols

            Missing: \(missingFiles.joined(separator: ", "))
            """

            Diagnostics.warning(warningMessage)
        }

        // Return empty commands - this plugin only checks, doesn't generate
        return []
    }
}
