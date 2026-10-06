import Foundation

/// Connection settings for a Confluence MCP server.
public struct ConfluenceConfig: Decodable {
    /// Base URL of the Confluence instance, e.g. https://confluence.example.com
    public let baseUrl: String
    /// Personal access token sent as a Bearer token.
    public let authToken: String

    public init(baseUrl: String, authToken: String) {
        self.baseUrl = baseUrl
        self.authToken = authToken
    }
}
