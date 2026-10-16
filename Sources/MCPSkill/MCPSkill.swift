import Foundation
import MCPServer
import Swifter

/// An MCP server that exposes reusable skills defined in SKILL.md files.
///
/// Skills are parsed once when the server is created; restart the server to pick up changes.
public final class MCPSkill {
    public let mcp: MCPServer

    public init(config: SkillConfig,
                server: HttpServer? = nil) throws {
        let catalog = try SkillCatalog(skillPaths: config.skillPaths)
        let serverConfig = MCPServerConfig(
            serverName: "MCP Skill",
            engines: [SkillEngine(catalog: catalog)]
        )
        self.mcp = MCPServer(config: serverConfig, server: server)
    }
}
