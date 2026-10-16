import Foundation

/// A skill loaded from a SKILL.md file.
struct Skill: Equatable {
    let name: String
    let description: String
    /// SKILL.md content without the frontmatter.
    let content: String
    /// Folder that contains SKILL.md and the files it references.
    let directoryURL: URL
}
