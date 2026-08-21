//
//  CoderEngine.swift
//  MCPServer
//
//  Created by: tomieq on 22/04/2026
//
import Foundation
import Swifter
import Logger
import MCPServer

enum CoderCommand: String {
    case file_tree
    case list_paths
    case find_file
    case read_file
    case file_stat
    case rename_file
    case override_file
    case create_new_file
    case delete_file
    case search_text
    case apply_patch
    case replace_text
    case replace_all
}

extension CoderCommand: CustomStringConvertible {
    var description: String {
        rawValue
    }
}

class CoderEngine: Engine {
    private let logger = Logger(CoderEngine.self)
    let folder: Folder
    let cache: FileCache
    private let responses: ToolResponseFactory

    init(folder: Folder, cache: FileCache) {
        self.folder = folder
        self.cache = cache
        self.responses = ToolResponseFactory()
    }

    let instructions = "Manage files beneath the configured project root. Use project-relative paths. Successful tool results are JSON text; failures are plain error text. Prefer bounded read_file calls and use apply_patch or guarded replacements for edits."

    func command(for rawValue: String) -> CoderCommand? {
        CoderCommand(rawValue: rawValue)
    }

    func canHandle(_ command: String) -> Bool {
        self.command(for: command).notNil
    }

    let tools: [ToolsList.Schema] = [
        .init(CoderCommand.file_tree,
              description: "List the project directory tree.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [:],
                            required: [])),
        .init(CoderCommand.list_paths,
              description: "List all project-relative file paths.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [:],
                            required: [])),
        .init(CoderCommand.find_file,
              description: "Find a project-relative path by filename or partial name.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filename": .init(type: .string, description: "Filename or partial filename to search for. No regex.")
                            ],
                            required: ["filename"])),
        .init(CoderCommand.read_file,
              description: "Read a bounded line range from one UTF-8 project-relative file. Defaults to 200 lines and 65,536 UTF-8 bytes; the structured response reports truncation and nextStartLine.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "Project-relative path of the file to read."),
                                "startLine": .init(type: .integer, description: "First line to return, starting at 1. Defaults to 1."),
                                "endLine": .init(type: .integer, description: "Last line to return, inclusive. Defaults to startLine plus 199."),
                                "maxBytes": .init(type: .integer, description: "Maximum UTF-8 bytes of content, from 1 through 1,048,576. Defaults to 65,536.")
                            ],
                            required: ["filepath"])),
        .init(CoderCommand.file_stat,
              description: "Read metadata for one project-relative path, including existence, type, byte size, dates, UTF-8/binary status, and optionally a SHA-256 hash.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "Project-relative path to inspect."),
                                "includeHash": .init(type: .boolean, description: "Include a SHA-256 hash for regular files. Defaults to false.")
                            ],
                            required: ["filepath"])),
        .init(CoderCommand.rename_file,
              description: "Rename or move one project-relative file. Creates missing destination directories.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "oldFilepath": .init(type: .string, description: "Current project-relative path."),
                                "newFilepath": .init(type: .string, description: "New project-relative path.")
                            ],
                            required: ["oldFilepath", "newFilepath"])),
        .init(CoderCommand.override_file,
              description: "Replace the entire UTF-8 contents of an existing project-relative file.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "Project-relative path of the file to overwrite."),
                                "content": .init(type: .string, description: "UTF-8 content to write.")
                            ],
                            required: ["filepath", "content"])),
        .init(CoderCommand.create_new_file,
              description: "Create a UTF-8 project-relative file and any missing parent directories. Fails if the file already exists.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "Project-relative path of the file to create."),
                                "content": .init(type: .string, description: "UTF-8 content to write.")
                            ],
                            required: ["filepath", "content"])),
        .init(CoderCommand.delete_file,
              description: "Delete a file from the project.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "Project-relative path of the file to delete.")
                            ],
                            required: ["filepath"])),
        .init(CoderCommand.search_text,
              description: "Search project files line-by-line using literal text or a regular expression. Supports case sensitivity, include/exclude path globs, a result limit, and surrounding context lines. Returns structured results.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "search": .init(type: .string, description: "Literal text or regular-expression pattern to search for."),
                                "useRegex": .init(type: .boolean, description: "Interpret search as a regular expression. Defaults to false."),
                                "caseSensitive": .init(type: .boolean, description: "Use case-sensitive matching. Defaults to true."),
                                "includeGlobs": .init(type: .array, items: .init(type: .string), description: "Optional path globs to include. Supports *, **, and ?."),
                                "excludeGlobs": .init(type: .array, items: .init(type: .string), description: "Optional path globs to exclude. Supports *, **, and ?."),
                                "limit": .init(type: .integer, description: "Maximum results, from 1 through 1,000. Defaults to 100."),
                                "contextLines": .init(type: .integer, description: "Context lines before and after each match, from 0 through 20. Defaults to 0.")
                            ],
                            required: ["search"])),
        .init(CoderCommand.apply_patch,
              description: "Apply a unified diff to project-relative UTF-8 text files without requiring Git. Use ---/+++ headers; a/ and b/ path prefixes are optional. Standard @@ -oldStart,oldCount +newStart,newCount @@ headers are supported, as are minimal @@ context-matched hunks. Multiple hunks and files are supported. Hunks first match exactly, then may use unique nearby or whitespace-insensitive context matching. dryRun returns structured JSON with target paths, match positions, match strategies, and added/removed line counts.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "patch": .init(type: .string, description: "A unified diff with --- and +++ file headers. Paths must be project-relative; a/ and b/ prefixes are optional. Prefer explicit line ranges; minimal @@ hunks need unique source context."),
                                "dryRun": .init(type: .boolean, description: "Validate without writing and return structured JSON diagnostics. Defaults to false.")
                            ],
                            required: ["patch"])),
        .init(CoderCommand.replace_text,
              description: "Replace exact text in one project-relative UTF-8 file. For safety, the current number of matches must exactly equal expectedMatches (which defaults to 1). Set replaceAll only when every verified match should change. Use dryRun to validate and return structured JSON without writing.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The project-relative path of the existing UTF-8 file."),
                                "find": .init(type: .string, description: "The non-empty exact text to find."),
                                "replace": .init(type: .string, description: "The text that replaces the match; it may be empty."),
                                "expectedMatches": .init(type: .integer, description: "Exact number of current matches required before writing. Defaults to 1."),
                                "replaceAll": .init(type: .boolean, description: "Replace every match after expectedMatches validation. Defaults to false."),
                                "dryRun": .init(type: .boolean, description: "Validate without writing and return structured JSON. Defaults to false.")
                            ],
                            required: ["filepath", "find", "replace"])),
        .init(CoderCommand.replace_all,
              description: "Replace exact text across all cached tracked files. Use with caution: the cached total must exactly match expectedMatches, and all files are revalidated from disk before any write. Always dry-run first.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "find": .init(type: .string, description: "The non-empty exact text to find in all cached project files."),
                                "replace": .init(type: .string, description: "The text that replaces every verified match; it may be empty."),
                                "expectedMatches": .init(type: .integer, description: "Exact total number of matches required across cached project files."),
                                "dryRun": .init(type: .boolean, description: "Validate without writing and return structured JSON. Defaults to false.")
                            ],
                            required: ["find", "replace", "expectedMatches"]))
    ]

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        do {
            return try execute(command, body: body)
        } catch {
            return responses.failure(error)
        }
    }

    private func execute(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard let command = self.command(for: command) else {
            return ToolResult([])
        }
        let dto: ToolResult
        switch command {
        case .file_tree:
            logger.d("🗄️ Tree of project's files")
            dto = responses.success(FileTreeResult(tree: folder.tree()))
        case .list_paths:
            logger.d("🗄️ List project's files")
            dto = responses.success(FilePathsResult(paths: folder.files()))
        case .find_file:
            struct File: Codable {
                let filename: String
            }
            let command: Command<File> = try body.decode()
            let filename = command.params?.arguments?.filename ?? ""

            logger.d("🔎 Find file \(filename)")
            dto = responses.success(FilePathsResult(paths: folder.files().filter { $0.contains(filename) }))
        case .read_file:
            struct File: Codable {
                let filepath: String
                let startLine: Int?
                let endLine: Int?
                let maxBytes: Int?
            }
            let command: Command<File> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""

            logger.d("👀 Read file content: \(virtualPath)")
            do {
                let filepath = try folder.projectURL(for: virtualPath)
                let arguments = command.params?.arguments
                let result = try FileReader().read(url: filepath,
                                                   filepath: virtualPath,
                                                   startLine: arguments?.startLine,
                                                   endLine: arguments?.endLine,
                                                   maxBytes: arguments?.maxBytes)
                dto = responses.success(result)
            } catch {
                dto = responses.failure(error, code: "read_failed")
            }
        case .file_stat:
            struct Action: Codable {
                let filepath: String
                let includeHash: Bool?
            }
            let command: Command<Action> = try body.decode()
            let arguments = command.params?.arguments
            let virtualPath = arguments?.filepath ?? ""
            do {
                let filepath = try folder.projectURL(for: virtualPath)
                dto = responses.success(try FileInspector().inspect(url: filepath,
                                                                    filepath: virtualPath,
                                                                    includeHash: arguments?.includeHash ?? false))
            } catch {
                dto = responses.failure(error, code: "stat_failed")
            }
        case .rename_file:
            struct Action: Codable {
                let oldFilepath: String
                let newFilepath: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.oldFilepath ?? ""
            let newVirtualpath = command.params?.arguments?.newFilepath ?? ""

            do {
                let filepath = try folder.projectURL(for: virtualPath)
                let newFilepath = try folder.projectURL(for: newVirtualpath)
                guard FileManager.default.fileExists(atPath: filepath.path) else {
                    dto = responses.failure("File not found at \(virtualPath)", code: "not_found")
                    break
                }
                guard FileManager.default.fileExists(atPath: newFilepath.path).not else {
                    dto = responses.failure("File already exists at \(newVirtualpath)", code: "already_exists")
                    break
                }
                try FileManager.default.createDirectory(at: newFilepath.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: filepath, to: newFilepath)
                logger.d("💾⚙️ Rename filename from \(virtualPath) ➡️ \(newVirtualpath)")
                dto = responses.success(FileMoveResult(oldFilepath: virtualPath, newFilepath: newVirtualpath))
            } catch {
                dto = responses.failure(error, code: "move_failed")
            }
        case .override_file:
            struct Action: Codable {
                let filepath: String
                let content: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            let content = command.params?.arguments?.content ?? ""

            do {
                let filepath = try folder.projectURL(for: virtualPath)
                guard FileManager.default.fileExists(atPath: filepath.path) else {
                    dto = responses.failure("File not found at \(virtualPath)", code: "not_found")
                    break
                }
                try content.write(to: filepath, atomically: true, encoding: .utf8)
                logger.d("💾🟠 Override file \(virtualPath)")
                dto = responses.success(FileWriteResult(filepath: virtualPath, changed: true))
            } catch {
                dto = responses.failure(error, code: "write_failed")
            }
        case .create_new_file:
            struct Action: Codable {
                let filepath: String
                let content: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            let content = command.params?.arguments?.content ?? ""

            do {
                let filepath = try folder.projectURL(for: virtualPath)
                guard FileManager.default.fileExists(atPath: filepath.path).not else {
                    dto = responses.failure("File already exists at \(virtualPath)", code: "already_exists")
                    break
                }
                try FileManager.default.createDirectory(at: filepath.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: filepath, atomically: true, encoding: .utf8)
                logger.d("💾🟢 Create file \(virtualPath)")
                dto = responses.success(FileWriteResult(filepath: virtualPath, changed: true))
            } catch {
                dto = responses.failure(error, code: "create_failed")
            }
        case .delete_file:
            struct Action: Codable {
                let filepath: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            do {
                let filepath = try folder.projectURL(for: virtualPath)
                guard FileManager.default.fileExists(atPath: filepath.path) else {
                    dto = responses.failure("File not found at \(virtualPath)", code: "not_found")
                    break
                }
                try FileManager.default.removeItem(at: filepath)
                logger.d("💾🔴 Delete file \(virtualPath)")
                dto = responses.success(FileDeleteResult(filepath: virtualPath, deleted: true))
            } catch {
                dto = responses.failure(error, code: "delete_failed")
            }
        case .search_text:
            struct Action: Codable {
                let search: String
                let useRegex: Bool?
                let caseSensitive: Bool?
                let includeGlobs: [String]?
                let excludeGlobs: [String]?
                let limit: Int?
                let contextLines: Int?
            }
            let command: Command<Action> = try body.decode()
            let arguments = command.params?.arguments
            let search = arguments?.search ?? ""
            logger.i("🔎 Searching text: \(search)")
            do {
                let options = SearchOptions(query: search,
                                            useRegex: arguments?.useRegex ?? false,
                                            caseSensitive: arguments?.caseSensitive ?? true,
                                            includeGlobs: arguments?.includeGlobs ?? [],
                                            excludeGlobs: arguments?.excludeGlobs ?? [],
                                            limit: arguments?.limit ?? 100,
                                            contextLines: arguments?.contextLines ?? 0)
                let matches = try cache.matching(options)
                dto = responses.success(SearchTextResult(results: matches.results,
                                                         limit: options.limit,
                                                         truncated: matches.truncated))
            } catch {
                dto = responses.failure(error, code: "search_failed")
            }
        case .apply_patch:
            struct Action: Codable {
                let patch: String
                let dryRun: Bool?
            }
            let command: Command<Action> = try body.decode()
            let patch = command.params?.arguments?.patch ?? ""
            let dryRun = command.params?.arguments?.dryRun ?? false

            do {
                let result = try UnifiedPatchApplier(rootURL: folder.realUrl).apply(patch, dryRun: dryRun)
                logger.d("💾🩹 \(result.message)")
                dto = responses.success(PatchToolResult(filesChanged: result.filesChanged,
                                                        changed: !dryRun,
                                                        dryRun: result.dryRun,
                                                        paths: result.paths,
                                                        report: result.report))
            } catch {
                dto = responses.failure(error, code: "patch_failed")
            }
        case .replace_text:
            struct Action: Codable {
                let filepath: String
                let find: String
                let replace: String
                let expectedMatches: Int?
                let replaceAll: Bool?
                let dryRun: Bool?
            }
            let command: Command<Action> = try body.decode()
            let arguments = command.params?.arguments

            do {
                let result = try TextReplacer(rootURL: folder.realUrl).replace(
                    filepath: arguments?.filepath ?? "",
                    find: arguments?.find ?? "",
                    replacement: arguments?.replace ?? "",
                    expectedMatches: arguments?.expectedMatches ?? 1,
                    replaceAll: arguments?.replaceAll ?? false,
                    dryRun: arguments?.dryRun ?? false
                )
                logger.d("💾🔁 \(result.message)")
                dto = responses.success(result)
            } catch {
                dto = responses.failure(error, code: "replace_failed")
            }
        case .replace_all:
            struct Action: Codable {
                let find: String
                let replace: String
                let expectedMatches: Int
                let dryRun: Bool?
            }
            let command: Command<Action> = try body.decode()
            let arguments = command.params?.arguments
            let find = arguments?.find ?? ""
            let dryRun = arguments?.dryRun ?? false

            do {
                let result = try TextReplacer(rootURL: folder.realUrl).replaceAll(
                    targets: cache.replacementTargets(find),
                    find: find,
                    replacement: arguments?.replace ?? "",
                    expectedMatches: arguments?.expectedMatches ?? 0,
                    dryRun: dryRun
                )
                logger.d("💾🔁 \(result.message)")
                dto = responses.success(result)
            } catch {
                dto = responses.failure(error, code: "replace_failed")
            }
        }
        return dto
    }
}
