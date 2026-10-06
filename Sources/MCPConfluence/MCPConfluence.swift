import MCPServer
import Swifter

/// An MCP server that fetches pages from Confluence.
public final class MCPConfluence {
    public let mcp: MCPServer

    public init(config: ConfluenceConfig, server: HttpServer? = nil) {
        let serverConfig = MCPServerConfig(
            serverName: "Confluence",
            engines: [ConfluenceEngine(config: config)]
        )
        self.mcp = MCPServer(config: serverConfig, server: server)
    }
}
