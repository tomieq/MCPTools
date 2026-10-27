import Foundation

/// Configuration for a shell MCP server that always starts commands in one project directory.
public struct ShellConfig: Decodable {
    /// Absolute path used as the working directory for every command.
    public let projectPath: String

    /// Additional directories to prepend to the `PATH` environment variable of every command.
    ///
    /// The server process inherits its `PATH` from wherever it was started, so binaries in other
    /// locations can be missing when tools run shell commands. Entries listed here are placed in
    /// front of the inherited `PATH`, in the given order, so their binaries are found first.
    public let additionalPathEntries: [String]

    public init(projectPath: String, additionalPathEntries: [String] = []) {
        self.projectPath = projectPath
        self.additionalPathEntries = additionalPathEntries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        struct Payload: Decodable {
            let projectPath: String
            let additionalPathEntries: [String]?
        }
        let payload = try container.decode(Payload.self)
        self.init(projectPath: payload.projectPath,
                  additionalPathEntries: payload.additionalPathEntries ?? [])
    }
}

/// Error thrown when a shell server configuration is invalid.
public enum ShellConfigurationError: LocalizedError {
    case invalidPathEntry(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPathEntry(let entry):
            return "Additional PATH entry must be a non-empty absolute path without NUL bytes: \(entry)"
        }
    }
}
