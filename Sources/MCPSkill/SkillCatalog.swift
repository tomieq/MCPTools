import Foundation
import Logger

enum SkillCatalogError: LocalizedError {
    case invalidSkillPath(String)
    case invalidSkill(String)

    var errorDescription: String? {
        switch self {
        case .invalidSkillPath(let path):
            return "Skill path is not a directory: \(path)"
        case .invalidSkill(let message):
            return message
        }
    }
}

/// Skills parsed at startup and kept in memory; new skills are added by `create`.
final class SkillCatalog {
    private static let skillFileName = "SKILL.md"
    private static let maximumContentBytes = 256 * 1024
    private static let maximumExtraFiles = 100
    private static let maximumExtraFilesBytes = 2 * 1024 * 1024
    private static let logger = Logger(SkillCatalog.self)

    private let lock = NSLock()
    private var loadedSkills: [Skill]
    /// New skills are stored here: the first configured path.
    private let storageRoot: URL?

    var skills: [Skill] {
        lock.lock()
        defer { lock.unlock() }
        return loadedSkills
    }

    init(skillPaths: [String]) throws {
        var skills: [Skill] = []
        var roots: [URL] = []
        for path in skillPaths {
            let root = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw SkillCatalogError.invalidSkillPath(path)
            }
            roots.append(root)

            for directory in Self.skillDirectories(in: root) {
                // The first skill wins when names collide across entry points.
                guard let skill = Self.loadSkill(in: directory),
                      !skills.contains(where: { $0.name == skill.name }) else {
                    continue
                }
                Self.logger.i("Loading skill: \(skill.name)")
                skills.append(skill)
            }
        }
        self.loadedSkills = skills
        self.storageRoot = roots.first
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name == name }
    }

    /// Stores a new skill as `<first path>/<name>/SKILL.md` plus `files` (skill-relative path to text content).
    /// Existing skills are never overwritten.
    func create(name: String, description: String, content: String, files: [String: String] = [:]) throws -> Skill {
        guard let storageRoot else {
            throw SkillCatalogError.invalidSkill("No skill path is configured")
        }
        guard Self.isValidName(name) else {
            throw SkillCatalogError.invalidSkill("name must be 1-64 characters: letters, digits, '-', '_' or '.', not starting with '.'")
        }
        let description = description.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty else {
            throw SkillCatalogError.invalidSkill("description must not be empty")
        }
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.utf8.count <= Self.maximumContentBytes, !body.contains("\0") else {
            throw SkillCatalogError.invalidSkill("content must not be empty and must be at most \(Self.maximumContentBytes) bytes")
        }
        let extraFiles = try Self.validatedExtraFiles(files)

        lock.lock()
        defer { lock.unlock() }
        let directory = storageRoot.appendingPathComponent(name, isDirectory: true)
        guard !loadedSkills.contains(where: { $0.name == name }),
              !FileManager.default.fileExists(atPath: directory.path) else {
            throw SkillCatalogError.invalidSkill("Skill already exists: \(name)")
        }

        let escapedDescription = description
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let markdown = "---\nname: \(name)\ndescription: \"\(escapedDescription)\"\n---\n\n\(body)\n"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try markdown.write(to: directory.appendingPathComponent(Self.skillFileName), atomically: true, encoding: .utf8)
            for (path, text) in extraFiles {
                let fileURL = directory.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        guard let skill = Self.loadSkill(in: directory) else {
            try? FileManager.default.removeItem(at: directory)
            throw SkillCatalogError.invalidSkill("Created skill could not be parsed")
        }
        Self.logger.i("Created skill: \(skill.name)")
        loadedSkills.append(skill)
        return skill
    }

    /// Returns the files with normalized relative paths, rejecting anything that could leave the skill folder.
    private static func validatedExtraFiles(_ files: [String: String]) throws -> [String: String] {
        guard files.count <= maximumExtraFiles else {
            throw SkillCatalogError.invalidSkill("At most \(maximumExtraFiles) extra files are allowed")
        }

        var result: [String: String] = [:]
        var totalBytes = 0
        for (path, text) in files {
            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty, !path.hasPrefix("/"), !path.contains("\0"), !path.contains("\\"),
                  components.allSatisfy({ $0 != ".." && $0 != "." && !$0.hasPrefix(".") }) else {
                throw SkillCatalogError.invalidSkill("Invalid file path: \(path). Use a relative path inside the skill folder without '..' or hidden components")
            }
            let normalized = components.joined(separator: "/")
            guard normalized.lowercased() != skillFileName.lowercased() else {
                throw SkillCatalogError.invalidSkill("\(skillFileName) is generated from content and cannot be passed as an extra file")
            }
            guard result[normalized] == nil else {
                throw SkillCatalogError.invalidSkill("Duplicate file path: \(normalized)")
            }
            guard !text.contains("\0") else {
                throw SkillCatalogError.invalidSkill("File is not text: \(path)")
            }
            totalBytes += text.utf8.count
            guard text.utf8.count <= maximumContentBytes, totalBytes <= maximumExtraFilesBytes else {
                throw SkillCatalogError.invalidSkill("Extra files are too large: at most \(maximumContentBytes) bytes per file and \(maximumExtraFilesBytes) bytes in total")
            }
            result[normalized] = text
        }
        return result
    }

    private static func isValidName(_ name: String) -> Bool {
        guard (1...64).contains(name.count), !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy {
            ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)))) || "-_.".unicodeScalars.contains($0)
        }
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
