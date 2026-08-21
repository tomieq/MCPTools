import MCPServer
import Swifter

/// An MCP server that executes one non-interactive shell command per SSH connection.
public final class MCPRemoteShell {
    public let mcp: MCPServer

    public init(config: RemoteShellConfig, server: HttpServer? = nil) {
        let serverConfig = MCPServerConfig(
            serverName: "Remote Shell",
            engines: [RemoteShellEngine(config: config)]
        )
        self.mcp = MCPServer(config: serverConfig, server: server)
    }
}
