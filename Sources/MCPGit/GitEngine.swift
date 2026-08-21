import Foundation
import MCPServer
import Swifter

private enum GitCommand: String, CustomStringConvertible {
    case repositoryInfo = "git_repository_info"
    case status = "git_status"
    case diff = "git_diff"
    case log = "git_log"
    case show = "git_show"
    case blame = "git_blame"
    case listFiles = "git_ls_files"
    case listBranches = "git_branch_list"
    case listRemotes = "git_remote_list"
    case listTags = "git_tag_list"
    case resolveRevisions = "git_rev_parse"
    case mergeBase = "git_merge_base"
    case compare = "git_compare"
    case conflicts = "git_conflicts"
    case stashes = "git_stash_list"
    case submodules = "git_submodule_status"
    case configGet = "git_config_get"

    var description: String { rawValue }
}

final class GitEngine: Engine {
    private let repository: GitRepository

    init(repository: GitRepository) {
        self.repository = repository
    }

    let instructions = "Read-only Git tools for the configured project root. They cannot modify Git state, files, branches, remotes, or repository configuration."

    func canHandle(_ command: String) -> Bool {
        GitCommand(rawValue: command) != nil
    }

    let tools: [ToolsList.Schema] = [
        .init(GitCommand.repositoryInfo, description: "Get repository root, HEAD, branch state, and shallow-clone status.", inputSchema: GitEngine.emptySchema),
        .init(GitCommand.status, description: "Get Git status, branch tracking, and optionally ignored files.", inputSchema: .init(properties: [
            "includeIgnored": GitEngine.property(.boolean, "Include ignored files."),
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths to limit the status.")
        ], required: [])),
        .init(GitCommand.diff, description: "Read a working-tree, staged, or two-revision diff. No changes are made.", inputSchema: .init(properties: [
            "mode": GitEngine.property(.string, "working, staged, or refs.", values: ["working", "staged", "refs"]),
            "baseRef": GitEngine.property(.string, "Base revision; required when mode is refs."),
            "targetRef": GitEngine.property(.string, "Target revision; required when mode is refs."),
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths."),
            "contextLines": GitEngine.property(.integer, "Patch context lines, from 0 through 100."),
            "statOnly": GitEngine.property(.boolean, "Return diff statistics instead of a patch."),
            "nameOnly": GitEngine.property(.boolean, "Return changed paths only.")
        ], required: [])),
        .init(GitCommand.log, description: "Read commit history without changing repository state.", inputSchema: .init(properties: [
            "ref": GitEngine.property(.string, "Revision to start from; defaults to HEAD."),
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths."),
            "limit": GitEngine.property(.integer, "Maximum commits, from 1 through 500."),
            "skip": GitEngine.property(.integer, "Number of commits to skip, from 0 through 10,000."),
            "author": GitEngine.property(.string, "Author pattern."),
            "since": GitEngine.property(.string, "Git date expression."),
            "until": GitEngine.property(.string, "Git date expression."),
            "firstParent": GitEngine.property(.boolean, "Follow only first-parent history."),
            "includePatch": GitEngine.property(.boolean, "Include patches in the result.")
        ], required: [])),
        .init(GitCommand.show, description: "Read one commit's metadata, files, and optional patch.", inputSchema: .init(properties: [
            "revision": GitEngine.property(.string, "Commit or other resolvable revision."),
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths."),
            "includePatch": GitEngine.property(.boolean, "Include the patch."),
            "statOnly": GitEngine.property(.boolean, "Return only diff statistics.")
        ], required: ["revision"])),
        .init(GitCommand.blame, description: "Read line attribution for one project-relative file.", inputSchema: .init(properties: [
            "path": GitEngine.property(.string, "Project-relative file path."),
            "startLine": GitEngine.property(.integer, "First line, starting at 1."),
            "endLine": GitEngine.property(.integer, "Last line, inclusive."),
            "ref": GitEngine.property(.string, "Revision; defaults to HEAD."),
            "ignoreWhitespace": GitEngine.property(.boolean, "Ignore whitespace changes.")
        ], required: ["path"])),
        .init(GitCommand.listFiles, description: "List tracked, untracked, ignored, or all project files.", inputSchema: .init(properties: [
            "scope": GitEngine.property(.string, "tracked, untracked, ignored, or all.", values: ["tracked", "untracked", "ignored", "all"]),
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths.")
        ], required: [])),
        .init(GitCommand.listBranches, description: "List local and/or remote branches with upstream metadata.", inputSchema: .init(properties: [
            "scope": GitEngine.property(.string, "local, remote, or all.", values: ["local", "remote", "all"]),
            "contains": GitEngine.property(.string, "Only branches containing this revision."),
            "mergedInto": GitEngine.property(.string, "Only branches merged into this revision."),
            "noMergedInto": GitEngine.property(.string, "Only branches not merged into this revision.")
        ], required: [])),
        //.init(GitCommand.listRemotes, description: "List configured remote names and fetch URLs.", inputSchema: GitEngine.emptySchema),
        .init(GitCommand.listTags, description: "List tags and target object IDs.", inputSchema: .init(properties: [
            "pattern": GitEngine.property(.string, "Glob pattern for tag names."),
            "contains": GitEngine.property(.string, "Only tags containing this revision."),
            "pointsAt": GitEngine.property(.string, "Only tags pointing at this revision."),
            "limit": GitEngine.property(.integer, "Maximum tags, from 1 through 500.")
        ], required: [])),
        .init(GitCommand.resolveRevisions, description: "Resolve revisions to immutable object IDs.", inputSchema: .init(properties: [
            "revisions": GitEngine.property(.array, itemsType: .string, "One or more revisions to resolve."),
            "verifyCommit": GitEngine.property(.boolean, "Require each revision to resolve to a commit.")
        ], required: ["revisions"])),
        .init(GitCommand.mergeBase, description: "Find the common ancestor of two revisions.", inputSchema: .init(properties: [
            "leftRef": GitEngine.property(.string, "First revision."),
            "rightRef": GitEngine.property(.string, "Second revision."),
            "all": GitEngine.property(.boolean, "Return all merge bases.")
        ], required: ["leftRef", "rightRef"])),
        .init(GitCommand.compare, description: "Compare two revisions and optionally include the diff.", inputSchema: .init(properties: [
            "baseRef": GitEngine.property(.string, "Base revision."),
            "targetRef": GitEngine.property(.string, "Target revision."),
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths."),
            "includePatch": GitEngine.property(.boolean, "Include the patch."),
            "statOnly": GitEngine.property(.boolean, "Return diff statistics only."),
            "nameOnly": GitEngine.property(.boolean, "Return changed paths only."),
            "contextLines": GitEngine.property(.integer, "Patch context lines, from 0 through 100.")
        ], required: ["baseRef", "targetRef"])),
        /* disabled
        .init(GitCommand.conflicts, description: "List files with unresolved Git conflicts.", inputSchema: .init(properties: [
            "pathspecs": GitEngine.property(.array, itemsType: .string, "Optional project-relative paths.")
        ], required: [])),
        .init(GitCommand.stashes, description: "List stashes without applying or modifying them.", inputSchema: .init(properties: [
            "limit": GitEngine.property(.integer, "Maximum stashes, from 1 through 500."),
            "includeStats": GitEngine.property(.boolean, "Include changed-file statistics.")
        ], required: [])),
        .init(GitCommand.submodules, description: "Read submodule commit and initialization status.", inputSchema: .init(properties: [
            "recursive": GitEngine.property(.boolean, "Include nested submodules.")
        ], required: [])),
        .init(GitCommand.configGet, description: "Read explicitly allowlisted local Git configuration keys.", inputSchema: .init(properties: [
            "keys": GitEngine.property(.array, itemsType: .string, "Allowed keys: remote.<name>.url, branch.<name>.remote, branch.<name>.merge, core.repositoryformatversion.")
        ], required: ["keys"]))
         */
    ]

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard let command = GitCommand(rawValue: command) else { return ToolResult([]) }
        do {
            switch command {
            case .repositoryInfo: return try result(repositoryInfo())
            case .status: return try result(status(body))
            case .diff: return try result(diff(body))
            case .log: return try result(log(body))
            case .show: return try result(show(body))
            case .blame: return try result(blame(body))
            case .listFiles: return try result(listFiles(body))
            case .listBranches: return try result(listBranches(body))
            case .listRemotes: return try result(listRemotes())
            case .listTags: return try result(listTags(body))
            case .resolveRevisions: return try result(resolveRevisions(body))
            case .mergeBase: return try result(mergeBase(body))
            case .compare: return try result(compare(body))
            case .conflicts: return try result(conflicts(body))
            case .stashes: return try result(stashes(body))
            case .submodules: return try result(submodules(body))
            case .configGet: return try result(configGet(body))
            }
        } catch {
            return ToolResult([error.localizedDescription])
        }
    }
}

private extension GitEngine {
    static let emptySchema = ToolParameter(type: .object, properties: [:], required: [])

    static func property(_ type: ValueType, itemsType: ValueType? = nil, _ description: String, values: [String]? = nil) -> ToolParameter.Property {
        .init(type: type, items: itemsType.isNil ? nil : .init(type: itemsType!), description: description, enumValues: values)
    }

    func result(_ command: ShellResult) throws -> ToolResult {
        guard command.succeeded else { throw GitToolError.commandFailed(command.output, command.status) }
        return encoded(GitToolSuccess(output: command.output.isEmpty ? "No results." : command.output))
    }

    func repositoryInfo() throws -> ShellResult {
        let head = try successful(["rev-parse", "HEAD"])
        let branchResult = try repository.run(["symbolic-ref", "--short", "-q", "HEAD"])
        let branch = branchResult.succeeded ? branchResult.output : "detached"
        let shallow = try successful(["rev-parse", "--is-shallow-repository"])
        return ShellResult(output: "root: \(repository.rootURL.path)\nhead: \(head.output)\nbranch: \(branch)\nshallow: \(shallow.output)", status: 0)
    }

    func status(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let includeIgnored: Bool?; let pathspecs: [String]? }
        let args: Arguments = try decode(body)
        var command = ["status", "--porcelain=v2", "--branch", "--untracked-files=all"]
        if args.includeIgnored == true { command.append("--ignored=matching") }
        return try run(command, paths: args.pathspecs)
    }

    func diff(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let mode, baseRef, targetRef: String?; let pathspecs: [String]?; let contextLines: Int?; let statOnly, nameOnly: Bool? }
        let args: Arguments = try decode(body)
        let mode = args.mode ?? "working"
        guard ["working", "staged", "refs"].contains(mode) else { throw GitToolError.invalidArgument("mode must be working, staged, or refs") }
        var command = ["diff", "--no-ext-diff", "--no-color"]
        if args.statOnly == true { command.append("--stat") }
        if args.nameOnly == true { command.append("--name-only") }
        if let context = try checked(args.contextLines, name: "contextLines", range: 0...100) { command.append("-U\(context)") }
        switch mode {
        case "staged": command.append("--cached")
        case "refs":
            guard let base = args.baseRef, let target = args.targetRef else { throw GitToolError.invalidArgument("baseRef and targetRef are required when mode is refs") }
            command += [try ref(base), try ref(target)]
        default: break
        }
        return try run(command, paths: args.pathspecs)
    }

    func log(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let ref: String?; let pathspecs: [String]?; let limit, skip: Int?; let author, since, until: String?; let firstParent, includePatch: Bool? }
        let args: Arguments = try decode(body)
        var command = ["log", "--no-ext-diff", "--no-color", "--date=iso-strict", "--pretty=format:%H%x09%an%x09%ae%x09%ad%x09%s"]
        if let limit = try checked(args.limit, name: "limit", range: 1...500) { command.append("-n\(limit)") }
        if let skip = try checked(args.skip, name: "skip", range: 0...10_000) { command.append("--skip=\(skip)") }
        if let author = args.author { command.append("--author=\(try text(author, name: "author"))") }
        if let since = args.since { command.append("--since=\(try text(since, name: "since"))") }
        if let until = args.until { command.append("--until=\(try text(until, name: "until"))") }
        if args.firstParent == true { command.append("--first-parent") }
        if args.includePatch == true { command.append("-p") }
        command.append(try ref(args.ref ?? "HEAD"))
        return try run(command, paths: args.pathspecs)
    }

    func show(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let revision: String; let pathspecs: [String]?; let includePatch, statOnly: Bool? }
        let args: Arguments = try decode(body)
        var command = ["show", "--no-ext-diff", "--no-color", "--date=iso-strict", "--format=fuller", try ref(args.revision)]
        if args.statOnly == true { command.append("--stat") }
        if args.includePatch == false { command.append("--no-patch") }
        return try run(command, paths: args.pathspecs)
    }

    func blame(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let path: String; let startLine, endLine: Int?; let ref: String?; let ignoreWhitespace: Bool? }
        let args: Arguments = try decode(body)
        let path = try projectPath(args.path)
        var command = ["blame", "--no-ext-diff", "--date=iso-strict"]
        if args.ignoreWhitespace == true { command.append("-w") }
        if let start = args.startLine {
            guard start > 0 else { throw GitToolError.invalidArgument("startLine must be at least 1") }
            let end = args.endLine ?? start
            guard end >= start else { throw GitToolError.invalidArgument("endLine must not precede startLine") }
            command += ["-L", "\(start),\(end)"]
        } else if args.endLine != nil {
            throw GitToolError.invalidArgument("endLine requires startLine")
        }
        command += [try ref(args.ref ?? "HEAD"), "--", path]
        return try repository.run(command)
    }

    func listFiles(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let scope: String?; let pathspecs: [String]? }
        let args: Arguments = try decode(body)
        let scope = args.scope ?? "tracked"
        var command = ["ls-files"]
        switch scope {
        case "tracked": break
        case "untracked": command.append("--others")
        case "ignored": command += ["--others", "--ignored", "--exclude-standard"]
        case "all": command += ["--cached", "--others", "--exclude-standard"]
        default: throw GitToolError.invalidArgument("scope must be tracked, untracked, ignored, or all")
        }
        return try run(command, paths: args.pathspecs)
    }

    func listBranches(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let scope, contains, mergedInto, noMergedInto: String? }
        let args: Arguments = try decode(body)
        let scope = args.scope ?? "local"
        var command = ["branch", "--no-color", "--format=%(HEAD)%(refname:short)%09%(objectname)%09%(upstream:short)%09%(upstream:trackshort)"]
        switch scope { case "local": break; case "remote": command.append("--remotes"); case "all": command.append("--all"); default: throw GitToolError.invalidArgument("scope must be local, remote, or all") }
        if let value = args.contains { command += ["--contains", try ref(value)] }
        if let value = args.mergedInto { command += ["--merged", try ref(value)] }
        if let value = args.noMergedInto { command += ["--no-merged", try ref(value)] }
        return try repository.run(command)
    }

    func listRemotes() throws -> ShellResult {
        let remotes = try successful(["remote"])
        let lines = try remotes.output.split(separator: "\n").map { remote in
            let name = String(remote)
            let url = try successful(["remote", "get-url", name]).output
            return "\(name)\t\(redactURL(url))"
        }
        return ShellResult(output: lines.joined(separator: "\n"), status: 0)
    }

    func listTags(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let pattern, contains, pointsAt: String?; let limit: Int? }
        let args: Arguments = try decode(body)
        var command = ["tag", "--format=%(refname:short)%09%(objectname)"]
        if let value = args.contains { command += ["--contains", try ref(value)] }
        if let value = args.pointsAt { command += ["--points-at", try ref(value)] }
        if let pattern = args.pattern {
            let pattern = try text(pattern, name: "pattern")
            guard pattern.hasPrefix("-").not else { throw GitToolError.invalidArgument("pattern must not begin with -") }
            command.append(pattern)
        }
        let output = try repository.run(command)
        if let limit = try checked(args.limit, name: "limit", range: 1...500) {
            return ShellResult(output: output.output.split(separator: "\n", omittingEmptySubsequences: false).prefix(limit).joined(separator: "\n"), status: output.status)
        }
        return output
    }

    func resolveRevisions(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let revisions: [String]; let verifyCommit: Bool? }
        let args: Arguments = try decode(body)
        guard args.revisions.isEmpty.not, args.revisions.count <= 100 else { throw GitToolError.invalidArgument("revisions must contain 1 through 100 values") }
        let suffix = args.verifyCommit == true ? "^{commit}" : "^{object}"
        var lines: [String] = []
        for value in args.revisions {
            let value = try ref(value)
            let output = try successful(["rev-parse", "--verify", "--quiet", "\(value)\(suffix)"])
            lines.append("\(value)\t\(output.output)")
        }
        return ShellResult(output: lines.joined(separator: "\n"), status: 0)
    }

    func mergeBase(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let leftRef, rightRef: String; let all: Bool? }
        let args: Arguments = try decode(body)
        var command = ["merge-base"]
        if args.all == true { command.append("--all") }
        command += [try ref(args.leftRef), try ref(args.rightRef)]
        return try repository.run(command)
    }

    func compare(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let baseRef, targetRef: String; let pathspecs: [String]?; let includePatch, statOnly, nameOnly: Bool?; let contextLines: Int? }
        let args: Arguments = try decode(body)
        let base = try ref(args.baseRef), target = try ref(args.targetRef)
        let mergeBase = try successful(["merge-base", base, target])
        var command = ["diff", "--no-ext-diff", "--no-color"]
        if args.statOnly == true { command.append("--stat") }
        if args.nameOnly == true { command.append("--name-only") }
        if args.includePatch == false { command.append("--no-patch") }
        if let context = try checked(args.contextLines, name: "contextLines", range: 0...100) { command.append("-U\(context)") }
        command += [base, target]
        let diff = try run(command, paths: args.pathspecs)
        return ShellResult(output: "merge-base: \(mergeBase.output)\n\n\(diff.output)", status: diff.status)
    }

    func conflicts(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let pathspecs: [String]? }
        let args: Arguments = try decode(body)
        return try run(["diff", "--name-only", "--diff-filter=U"], paths: args.pathspecs)
    }

    func stashes(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let limit: Int?; let includeStats: Bool? }
        let args: Arguments = try decode(body)
        var command = ["stash", "list", "--date=iso-strict"]
        if let limit = try checked(args.limit, name: "limit", range: 1...500) { command.append("-n\(limit)") }
        if args.includeStats == true { command.append("--stat") }
        return try repository.run(command)
    }

    func submodules(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let recursive: Bool? }
        let args: Arguments = try decode(body)
        return try repository.run(args.recursive == true ? ["submodule", "status", "--recursive"] : ["submodule", "status"])
    }

    func configGet(_ body: HttpRequestBody) throws -> ShellResult {
        struct Arguments: Decodable { let keys: [String] }
        let args: Arguments = try decode(body)
        guard args.keys.isEmpty.not, args.keys.count <= 50 else { throw GitToolError.invalidArgument("keys must contain 1 through 50 values") }
        var lines: [String] = []
        for key in args.keys {
            guard isAllowedConfigKey(key) else { throw GitToolError.invalidArgument("Configuration key is not allowlisted: \(key)") }
            let value = try repository.run(["config", "--local", "--get-all", key])
            guard value.succeeded || value.status == 1 else { throw GitToolError.commandFailed(value.output, value.status) }
            let output = key.hasSuffix(".url") ? redactURL(value.output) : value.output
            lines.append("\(key): \(output.isEmpty ? "(not set)" : output)")
        }
        return ShellResult(output: lines.joined(separator: "\n"), status: 0)
    }

    func run(_ command: [String], paths: [String]?) throws -> ShellResult {
        guard let paths, paths.isEmpty.not else { return try repository.run(command) }
        return try repository.run(command + ["--"] + paths.map { try projectPath($0) })
    }

    func successful(_ command: [String]) throws -> ShellResult {
        let result = try repository.run(command)
        guard result.succeeded else { throw GitToolError.commandFailed(result.output, result.status) }
        return result
    }

    func decode<T: Decodable>(_ body: HttpRequestBody, as type: T.Type = T.self) throws -> T {
        let command: Command<T> = try body.decode()
        guard let arguments = command.params?.arguments else { throw GitToolError.invalidArgument("Missing tool arguments") }
        return arguments
    }

    func ref(_ value: String) throws -> String {
        let value = try text(value, name: "revision")
        guard value.hasPrefix("-").not else { throw GitToolError.invalidArgument("Revision must not begin with -") }
        return value
    }

    func text(_ value: String, name: String) throws -> String {
        guard value.isEmpty.not, value.count <= 1_024, value.contains("\0").not, value.contains("\n").not else { throw GitToolError.invalidArgument("Invalid \(name)") }
        return value
    }

    func projectPath(_ value: String) throws -> String {
        let value = try text(value, name: "path")
        let url = URL(fileURLWithPath: value, relativeTo: repository.rootURL).standardizedFileURL
        guard value.hasPrefix("/").not, url.path.hasPrefix(repository.rootURL.path + "/") else { throw GitToolError.invalidArgument("Path must remain within the project root") }
        return value
    }

    func checked(_ value: Int?, name: String, range: ClosedRange<Int>) throws -> Int? {
        guard let value else { return nil }
        guard range.contains(value) else { throw GitToolError.invalidArgument("\(name) must be between \(range.lowerBound) and \(range.upperBound)") }
        return value
    }

    func isAllowedConfigKey(_ key: String) -> Bool {
        if key == "core.repositoryformatversion" { return true }
        let parts = key.split(separator: ".")
        if parts.count == 3, parts[0] == "remote", parts[2] == "url" { return true }
        return parts.count == 3 && parts[0] == "branch" && (parts[2] == "remote" || parts[2] == "merge")
    }

    func redactURL(_ value: String) -> String {
        guard let schemeRange = value.range(of: "://"), let atRange = value.range(of: "@", range: schemeRange.upperBound..<value.endIndex) else { return value }
        return String(value[..<schemeRange.upperBound]) + "***@" + String(value[atRange.upperBound...])
    }
}

private struct GitToolSuccess: Encodable {
    let ok = true
    let output: String
}

private extension GitEngine {
    func encoded<T: Encodable>(_ value: T) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fallback = "Could not serialize Git response"
        let text = (try? String(data: encoder.encode(value), encoding: .utf8)) ?? fallback
        return ToolResult([text])
    }
}

private enum GitToolError: LocalizedError {
    case invalidArgument(String)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        case .commandFailed(let output, let status): return "git exited with status \(status): \(output)"
        }
    }
}

private extension Bool {
    var not: Bool { !self }
}
