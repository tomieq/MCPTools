import Foundation
import Logger

enum SkillCatalogError: LocalizedError {
    case invalidSkillPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidSkillPath(let path):
            return "Skill path is not a directory: \(path)"
        }
    }
}

/// Skills parsed once at startup and kept in memory.
final class SkillCatalog {
    private static let skillFileName = "SKILL.md"
    private let logger = Logger(SkillCatalog.self)

    let skills: [Skill]

    init(skillPaths: [String]) throws {
        var skills: [Skill] = []
        for path in skillPaths {
            let root = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw SkillCatalogError.invalidSkillPath(path)
            }

            for directory in Self.skillDirectories(in: root) {
                // The first skill wins when names collide across entry points.
                guard let skill = Self.loadSkill(in: directory),
                      !skills.contains(where: { $0.name == skill.name }) else {
                    continue
                }
                logger.i("Loading skill: \(skill.name)")
                skills.append(skill)
            }
        }
        self.skills = skills
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name == name }
    }

    private static func skillDirectories(in root: URL) -> [URL] {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(skillFileName).path) {
            return [root]
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func loadSkill(in directory: URL) -> Skill? {
        let fileURL = directory.appendingPathComponent(skillFileName)
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return SkillParser.parse(markdown: markdown, directoryURL: directory)
    }
}
