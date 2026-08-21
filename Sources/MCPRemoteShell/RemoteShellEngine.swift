import Foundation
import MCPServer
import Swifter

private enum RemoteShellCommand: String, CustomStringConvertible {
    case sh

    var description: String { rawValue }
}

final class RemoteShellEngine: Engine {
    private let config: RemoteShellConfig

    init(config: RemoteShellConfig) {
        self.config = config
    }

    let instructions = "Execute commands on the configured remote machine. Each sh call opens a separate SSH connection; it is not a live session, so state such as the working directory does not persist between calls. Commands must be non-interactive because MCP tool calls cannot provide an interactive terminal session."

    let tools: [ToolsList.Schema] = [
        .init(RemoteShellCommand.sh,
              description: "Execute a non-interactive command on the configured remote machine. Each call creates a separate SSH connection, not a live session; shell state does not persist between calls. Interactive commands are unsupported.",
              inputSchema: .init(properties: [
                  "command": .init(type: .string, description: "Non-interactive command to execute on the remote machine.")
              ], required: ["command"]))
    ]

    func canHandle(_ command: String) -> Bool {
        RemoteShellCommand(rawValue: command) != nil
    }

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard RemoteShellCommand(rawValue: command) == .sh else { return ToolResult([]) }
        do {
            let request: Command<Arguments> = try body.decode()
            guard let arguments = request.params?.arguments else {
                throw RemoteShellError.invalidArgument("Missing tool arguments")
            }
            return response(try run(command: arguments.command))
        } catch {
            return ToolResult([error.localizedDescription])
        }
    }
}

private extension RemoteShellEngine {
    func run(command: String) throws -> RemoteShellResult {
        guard command.isEmpty.not, command.contains("\0").not else {
            throw RemoteShellError.invalidArgument("command must not be empty or contain NUL bytes")
        }

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

    func response(_ result: RemoteShellResult) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? String(data: encoder.encode(result), encoding: .utf8))
            ?? "Could not serialize remote shell response"
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
