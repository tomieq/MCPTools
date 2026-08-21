import Foundation
import MCPServer
import Swifter

/// An MCP server that runs shell commands with a fixed project working directory.
///
/// This is intentionally not a filesystem sandbox: a shell command can still access files that
/// the server process itself is permitted to access. Use a sandboxed OS account or container when
/// stronger isolation is required.
public final class MCPShell {
    public let mcp: MCPServer

    public init(config: ShellConfig,
                server: HttpServer? = nil) throws {
        let projectDirectory = try ShellProjectDirectory(projectPath: config.projectPath)
        let serverConfig = MCPServerConfig(
            serverName: "MCP Shell",
            engines: [ShellEngine(projectDirectory: projectDirectory)]
        )
        self.mcp = MCPServer(config: serverConfig, server: server)
    }
}