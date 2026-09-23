import Dispatch
import Foundation
import MCPServer
import Swifter

private enum ShellCommand: String, CustomStringConvertible {
    case run = "shell_run"
    case spawn = "shell_spawn"

    var description: String { rawValue }
}

final class ShellEngine: Engine {
    private let projectDirectory: ShellProjectDirectory
    init(projectDirectory: ShellProjectDirectory) {
        self.projectDirectory = projectDirectory
    }

    let instructions = "Run shell commands with the configured project directory as the fixed initial working directory. Use this only when no dedicated MCP tool fits. Use shell_spawn for long-lived processes; it returns immediately and discards all process output. These tools may change files and run arbitrary executables. They are not a filesystem sandbox."

    let tools: [ToolsList.Schema] = [
        .init(ShellCommand.run,
              description: "Run a zsh command in the fixed project directory. Use this only as a fallback when no dedicated tool fits. Supports shell syntax such as pipes and redirects. The working directory cannot be supplied by the caller. Output is capped and the structured response reports truncation. Optional environment variables apply only to this command.",
              inputSchema: .init(properties: [
                  "command": .init(type: .string, description: "Shell command to run from the project directory."),
                  "environment": .init(type: .object, description: "String-to-string environment variables for this command only."),
                  "timeoutSeconds": .init(type: .integer, description: "Maximum runtime in seconds, from 1 through 900; defaults to 300."),
                  "maxOutputBytes": .init(type: .integer, description: "Maximum combined stdout/stderr bytes to return, from 1 through 1,048,576; defaults to 65,536.")
              ], required: ["command"])),
        .init(ShellCommand.spawn,
              description: "Start a long-lived zsh command in the fixed project directory and return immediately with its process ID. Run the application in the foreground; do not add nohup, output redirects, or background operators. Standard input, output, and error are discarded, and the process is not stopped when the tool call completes. The working directory cannot be supplied by the caller. Optional environment variables apply only to the spawned process.",
              inputSchema: .init(properties: [
                  "command": .init(type: .string, description: "Long-lived shell command to start from the project directory."),
                  "environment": .init(type: .object, description: "String-to-string environment variables for the spawned process only.")
              ], required: ["command"]))
    ]

    func canHandle(_ command: String) -> Bool {
        ShellCommand(rawValue: command) != nil
    }

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        do {
            switch ShellCommand(rawValue: command) {
            case .run:
                let request: Command<Arguments> = try body.decode()
                guard let arguments = request.params?.arguments else {
                    throw ShellToolError.invalidArgument("Missing tool arguments")
                }
                return response(try run(arguments))
            case .spawn:
                let request: Command<SpawnArguments> = try body.decode()
                guard let arguments = request.params?.arguments else {
                    throw ShellToolError.invalidArgument("Missing tool arguments")
                }
                return response(try spawn(arguments))
            case nil:
                return ToolResult([])
            }
        } catch {
            return failure(error)
        }
    }
}

private extension ShellEngine {
    func run(_ arguments: Arguments) throws -> ShellExecutionResult {
        let command = try validatedCommand(arguments.command)
        let timeout = try validatedTimeout(arguments.timeoutSeconds)
        let maximumOutputBytes = try validatedMaximumOutput(arguments.maxOutputBytes)
        let environment = try buildEnvironment(arguments.environment ?? [:])

        let task = Process()
        let outputPipe = Pipe()
        let collector = OutputCollector(maximumBytes: maximumOutputBytes)
        let outputFinished = DispatchGroup()
        outputFinished.enter()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outputFinished.leave()
            } else {
                collector.append(data)
            }
        }
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.currentDirectoryURL = projectDirectory.url
        task.environment = environment
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        let state = TimeoutState()
        let timeoutWork = DispatchWorkItem {
            guard task.isRunning else { return }
            state.markTimedOut()
            task.terminate()
        }
        try task.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutWork)
        task.waitUntilExit()
        timeoutWork.cancel()
        outputFinished.wait()

        return ShellExecutionResult(
            output: String(decoding: collector.data, as: UTF8.self).trimmingCharacters(in: .newlines),
            status: task.terminationStatus,
            timedOut: state.timedOut,
            truncated: collector.truncated,
            outputBytes: collector.totalBytes
        )
    }

    func spawn(_ arguments: SpawnArguments) throws -> ShellSpawnResult {
        let command = try validatedCommand(arguments.command)
        let environment = try buildEnvironment(arguments.environment ?? [:])
        let task = Process()
        let nullDevice = FileHandle.nullDevice
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.currentDirectoryURL = projectDirectory.url
        task.environment = environment
        task.standardInput = nullDevice
        task.standardOutput = nullDevice
        task.standardError = nullDevice

        try task.run()
        let processIdentifier = task.processIdentifier
        DispatchQueue.global(qos: .utility).async {
            task.waitUntilExit()
        }
        return ShellSpawnResult(processIdentifier: processIdentifier)
    }

    func validatedCommand(_ command: String) throws -> String {
        guard command.isEmpty.not, command.count <= 100_000, command.contains("\0").not else {
            throw ShellToolError.invalidArgument("command must be between 1 and 100,000 characters and contain no NUL bytes")
        }
        return command
    }

    func validatedTimeout(_ value: Int?) throws -> Int {
        let timeout = value ?? 300
        guard (1...900).contains(timeout) else {
            throw ShellToolError.invalidArgument("timeoutSeconds must be between 1 and 900")
        }
        return timeout
    }

    func validatedMaximumOutput(_ value: Int?) throws -> Int {
        let maximum = value ?? 64 * 1024
        guard (1...1_048_576).contains(maximum) else {
            throw ShellToolError.invalidArgument("maxOutputBytes must be between 1 and 1,048,576")
        }
        return maximum
    }

    func buildEnvironment(_ requested: [String: String]) throws -> [String: String] {
        guard requested.count <= 100 else {
            throw ShellToolError.invalidArgument("environment may contain at most 100 variables")
        }
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in requested {
            guard isValidEnvironmentKey(key), value.contains("\0").not else {
                throw ShellToolError.invalidArgument("Invalid environment variable: \(key)")
            }
            environment[key] = value
        }
        return environment
    }

    func isValidEnvironmentKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, first.properties.isAlphabetic || first == "_" else { return false }
        return key.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == "_" }
    }
}

private struct Arguments: Decodable {
    let command: String
    let environment: [String: String]?
    let timeoutSeconds: Int?
    let maxOutputBytes: Int?
}

private struct SpawnArguments: Decodable {
    let command: String
    let environment: [String: String]?
}

private struct ShellExecutionResult: Encodable {
    let output: String
    let status: Int32
    let timedOut: Bool
    let truncated: Bool
    let outputBytes: Int
}

private struct ShellResponse: Encodable {
    let ok: Bool
    let exitStatus: Int32
    let timedOut: Bool
    let truncated: Bool
    let outputBytes: Int
    let output: String
}

private struct ShellSpawnResult: Encodable {
    let processIdentifier: Int32
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var storedData = Data()
    private var capturedBytes = 0
    private var wasTruncated = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        capturedBytes += data.count
        let remaining = maximumBytes - storedData.count
        if remaining > 0 {
            storedData.append(data.prefix(remaining))
        }
        if data.count > remaining {
            wasTruncated = true
        }
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }

    var totalBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedBytes
    }

    var truncated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wasTruncated
    }
}

private extension ShellEngine {
    func response(_ result: ShellExecutionResult) -> ToolResult {
        let payload = ShellResponse(ok: true,
                                    exitStatus: result.status,
                                    timedOut: result.timedOut,
                                    truncated: result.truncated,
                                    outputBytes: result.outputBytes,
                                    output: result.output)
        return encoded(payload)
    }

    func response(_ result: ShellSpawnResult) -> ToolResult {
        encoded(result)
    }

    func failure(_ error: Error) -> ToolResult {
        ToolResult([error.localizedDescription])
    }

    func encoded<T: Encodable>(_ value: T) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fallback = "Could not serialize shell response"
        let text = (try? String(data: encoder.encode(value), encoding: .utf8)) ?? fallback
        return ToolResult([text])
    }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private enum ShellToolError: LocalizedError {
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        }
    }
}
