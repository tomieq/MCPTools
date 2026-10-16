import Foundation
import MCPServer
import Swifter

private enum SkillCommand: String, CustomStringConvertible {
    case list = "skill_list"
    case load = "skill_load"
    case readFile = "skill_read_file"
    case create = "skill_create"

    var description: String { rawValue }
}

final class SkillEngine: Engine {
    private static let maximumFileBytes = 256 * 1024
    private static let maximumListedFiles = 200

    private let catalog: SkillCatalog

    // Computed so skills created at runtime show up in later tool listings.
    var instructions: String {
        "Provides skills: reusable, task-specific instructions. When a task matches a skill description, call skill_load and follow the returned instructions. Files referenced by a skill can be read with skill_read_file. Use skill_create to save a new reusable skill.\nAvailable skills:\n\(summary)"
    }

    var tools: [ToolsList.Schema] {
        [
            .init(SkillCommand.list,
                  description: "List all available skills with their descriptions.",
                  inputSchema: .init(properties: [:], required: [])),
            .init(SkillCommand.load,
                  description: "Load the full instructions of a skill. Call it when the task matches a skill description, then follow the returned instructions.\nAvailable skills:\n\(summary)",
                  inputSchema: .init(properties: [
                      "name": .init(type: .string, description: "Name of the skill to load.")
                  ], required: ["name"])),
            .init(SkillCommand.readFile,
                  description: "Read a UTF-8 text file that belongs to a skill, for example a reference or script mentioned in its instructions. Only files inside the skill folder can be read.",
                  inputSchema: .init(properties: [
                      "name": .init(type: .string, description: "Name of the skill that owns the file."),
                      "path": .init(type: .string, description: "File path relative to the skill folder.")
                  ], required: ["name", "path"])),
            .init(SkillCommand.create,
                  description: "Create a new skill from the given instructions so it can be loaded in future sessions. It is stored in the primary skill folder. An existing skill is never overwritten.",
                  inputSchema: .init(properties: [
                      "name": .init(type: .string, description: "Unique skill name, also used as the folder name: letters, digits, '-', '_' or '.', at most 64 characters."),
                      "description": .init(type: .string, description: "One sentence saying what the skill does and when to use it."),
                      "content": .init(type: .string, description: "Skill instructions in Markdown, without frontmatter.")
                  ], required: ["name", "description", "content"]))
        ]
    }

    init(catalog: SkillCatalog) {
        self.catalog = catalog
    }

    private var summary: String {
        let skills = catalog.skills
        return skills.isEmpty
            ? "No skills are available."
            : skills.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
    }

    func canHandle(_ command: String) -> Bool {
        SkillCommand(rawValue: command) != nil
    }

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        do {
            switch SkillCommand(rawValue: command) {
            case .list:
                return ToolResult([list()])
            case .load:
                let request: Command<LoadArguments> = try body.decode()
                guard let arguments = request.params?.arguments else {
                    throw SkillToolError.invalidArgument("Missing tool arguments")
                }
                return ToolResult([try load(arguments)])
            case .readFile:
                let request: Command<ReadFileArguments> = try body.decode()
                guard let arguments = request.params?.arguments else {
                    throw SkillToolError.invalidArgument("Missing tool arguments")
                }
                return ToolResult([try readFile(arguments)])
            case .create:
                let request: Command<CreateArguments> = try body.decode()
                guard let arguments = request.params?.arguments else {
                    throw SkillToolError.invalidArgument("Missing tool arguments")
                }
                let skill = try catalog.create(name: arguments.name,
                                               description: arguments.description,
                                               content: arguments.content)
                return ToolResult(["Skill created: \(skill.name) (\(skill.directoryURL.path))"])
            case nil:
                return ToolResult([])
            }
        } catch {
            return ToolResult([error.localizedDescription])
        }
    }
}

private extension SkillEngine {
    func list() -> String {
        let entries = catalog.skills.map { SkillSummary(name: $0.name, description: $0.description) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? String(data: encoder.encode(entries), encoding: .utf8)) ?? "[]"
    }

    func load(_ arguments: LoadArguments) throws -> String {
        let skill = try skill(named: arguments.name)
        var text = "Skill directory: \(skill.directoryURL.path)\n\n\(skill.content)"
        let files = supportingFiles(of: skill)
        if !files.isEmpty {
            text += "\n\nFiles in the skill folder (read them with skill_read_file):\n"
            text += files.map { "- \($0)" }.joined(separator: "\n")
        }
        return text
    }

    func readFile(_ arguments: ReadFileArguments) throws -> String {
        let skill = try skill(named: arguments.name)
        guard !arguments.path.isEmpty, !arguments.path.contains("\0") else {
            throw SkillToolError.invalidArgument("path must be a non-empty relative path")
        }

        let base = skill.directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let target = base.appendingPathComponent(arguments.path).resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(base.path + "/") else {
            throw SkillToolError.invalidArgument("path must stay inside the skill folder")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw SkillToolError.invalidArgument("File not found: \(arguments.path)")
        }
        let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maximumFileBytes else {
            throw SkillToolError.invalidArgument("File is larger than \(Self.maximumFileBytes) bytes")
        }
        guard let text = try? String(contentsOf: target, encoding: .utf8) else {
            throw SkillToolError.invalidArgument("File is not valid UTF-8 text")
        }
        return text
    }

    func skill(named name: String) throws -> Skill {
        guard let skill = catalog.skill(named: name) else {
            let available = catalog.skills.map(\.name).joined(separator: ", ")
            throw SkillToolError.invalidArgument("Unknown skill: \(name). Available skills: \(available)")
        }
        return skill
    }

    // Relative paths of files next to SKILL.md, capped to keep the response small.
    func supportingFiles(of skill: Skill) -> [String] {
        let base = skill.directoryURL.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relativePath = String(url.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(base.path.count + 1))
            if relativePath != "SKILL.md" {
                files.append(relativePath)
            }
        }
        return Array(files.sorted().prefix(Self.maximumListedFiles))
    }
}

private struct LoadArguments: Decodable {
    let name: String
}

private struct ReadFileArguments: Decodable {
    let name: String
    let path: String
}

private struct CreateArguments: Decodable {
    let name: String
    let description: String
    let content: String
}

private struct SkillSummary: Encodable {
    let name: String
    let description: String
}

private enum SkillToolError: LocalizedError {
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        }
    }
}
