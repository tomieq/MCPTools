import Foundation

/// Configuration for a skill MCP server.
public struct SkillConfig: Decodable {
    /// Absolute paths of entry points. Each one is a folder of skill folders (`<path>/<skill>/SKILL.md`)
    /// or a single skill folder that contains SKILL.md itself.
    public let skillPaths: [String]

    public init(skillPaths: [String]) {
        self.skillPaths = skillPaths
    }
}
