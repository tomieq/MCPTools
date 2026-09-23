import Foundation
import MCPServer
import Swifter

private enum RemoteShellCommand: String, CustomStringConvertible {
    case sh
    case spawn

    var description: String { rawValue }
}

final class RemoteShellEngine: Engine {
    private let config: RemoteShellConfig

    init(config: RemoteShellConfig) {
        self.config = config
    }

    let instructions = "Execute commands on the configured remote machine. Each sh call opens a separate SSH connection; it is not a live session, so state such as the working directory does not persist between calls. Use spawn to start a long-lived remote process and return its process ID. Commands must be non-interactive because MCP tool calls cannot provide an interactive terminal session."

    let tools: [ToolsList.Schema] = [
        .init(RemoteShellCommand.sh,
              description: "Execute a non-interactive command on the configured remote machine. Each call creates a separate SSH connection, not a live session; shell state does not persist between calls. Interactive commands are unsupported.",
              inputSchema: .init(properties: [
                  "command": .init(type: .string, description: "Non-interactive command to execute on the remote machine.")
              ], required: ["command"])),
        .init(RemoteShellCommand.spawn,
              description: "Start a long-lived command on the remote machine and return its process ID. Run the application in the foreground; do not add nohup, output redirects, or background operators. Standard input, output, and error are discarded, and the process is not stopped when the SSH connection closes.",
              inputSchema: .init(properties: [
                  "command": .init(type: .string, description: "Long-lived command to start on the remote machine.")
              ], required: ["command"]))
    ]

    func canHandle(_ command: String) -> Bool {
        RemoteShellCommand(rawValue: command) != nil
    }

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        do {
            let request: Command<Arguments> = try body.decode()
            guard let arguments = request.params?.arguments else {
                throw RemoteShellError.invalidArgument("Missing tool arguments")
            }
            switch RemoteShellCommand(rawValue: command) {
            case .sh:
                return response(try run(command: arguments.command))
            case .spawn:
                return response(try spawn(command: arguments.command))
            case nil:
                return ToolResult([])
            }
        } catch {
            return ToolResult([error.localizedDescription])
        }
    }
}

private extension RemoteShellEngine {
    func run(command: String) throws -> RemoteShellResult {
        let command = try validatedCommand(command)

        let task = Process()
        let outputPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["sshpass", "-p", config.password, "ssh", "\(config.user)@\(config.host)", command]
        task.environment = ProcessInfo.processInfo.environment.merging(
            ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"],
            uniquingKeysWith: { _, new in new }
        )
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        try task.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return RemoteShellResult(
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines),
            exitStatus: task.terminationStatus
        )
    }

    func spawn(command: String) throws -> RemoteShellSpawnResult {
        let command = try validatedCommand(command)
        let task = Process()
        let outputPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["sshpass", "-p", config.password, "ssh", "\(config.user)@\(config.host)", remoteSpawnCommand(command)]
        task.environment = ProcessInfo.processInfo.environment.merging(
            ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"],
            uniquingKeysWith: { _, new in new }
        )
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        try task.run()
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        task.waitUntilExit()

        return RemoteShellSpawnResult(
            processIdentifier: processIdentifier(from: output),
            exitStatus: task.terminationStatus,
            output: output
        )
    }

    func validatedCommand(_ command: String) throws -> String {
        guard command.isEmpty.not, command.contains("\0").not else {
            throw RemoteShellError.invalidArgument("command must not be empty or contain NUL bytes")
        }
        return command
    }

    func remoteSpawnCommand(_ command: String) -> String {
        "nohup /bin/sh -c \(shellQuoted(command)) </dev/null >/dev/null 2>&1 & printf '%s\\n' \"$!\""
    }

    func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }

    func processIdentifier(from output: String) -> Int32? {
        output.split(whereSeparator: \ .isNewline).reversed().compactMap { Int32($0) }.first
    }

    func response(_ result: RemoteShellResult) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? String(data: encoder.encode(result), encoding: .utf8))
            ?? "Could not serialize remote shell response"
        return ToolResult([text])
    }

    func response(_ result: RemoteShellSpawnResult) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? String(data: encoder.encode(result), encoding: .utf8))
            ?? "Could not serialize remote shell spawn response"
        return ToolResult([text])
    }
}

private struct Arguments: Decodable {
    let command: String
}

private struct RemoteShellResult: Encodable {
    let output: String
    let exitStatus: Int32
}

private struct RemoteShellSpawnResult: Encodable {
    let processIdentifier: Int32?
    let exitStatus: Int32
    let output: String
}

private enum RemoteShellError: LocalizedError {
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        }
    }
}

private extension Bool {
    var not: Bool { !self }
}
