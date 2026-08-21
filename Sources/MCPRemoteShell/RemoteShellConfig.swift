import Foundation

/// Connection settings for a RemoteShell MCP server.
public struct RemoteShellConfig: Decodable {
    public let user: String
    public let password: String
    public let host: String

    public init(user: String, password: String, host: String) {
        self.user = user
        self.password = password
        self.host = host
    }
}
