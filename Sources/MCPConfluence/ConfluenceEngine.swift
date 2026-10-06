import Foundation
import MCPServer
import Swifter
import WebResponse

private enum ConfluenceCommand: String, CustomStringConvertible {
    case getPage = "get_page"

    var description: String { rawValue }
}

final class ConfluenceEngine: Engine {
    private let config: ConfluenceConfig

    init(config: ConfluenceConfig) {
        self.config = config
    }

    let instructions = "Fetch pages from Confluence by page ID. The page body is returned in Confluence storage format (XHTML)."

    let tools: [ToolsList.Schema] = [
        .init(ConfluenceCommand.getPage,
              description: "Fetch a Confluence page by its numeric page ID and return its title, space, version and body in storage format.",
              inputSchema: .init(properties: [
                  "pageId": .init(type: .string, description: "Numeric ID of the Confluence page.")
              ], required: ["pageId"]))
    ]

    func canHandle(_ command: String) -> Bool {
        ConfluenceCommand(rawValue: command) != nil
    }

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        do {
            let request: Command<Arguments> = try body.decode()
            guard let arguments = request.params?.arguments else {
                throw ConfluenceError.invalidArgument("Missing tool arguments")
            }
            switch ConfluenceCommand(rawValue: command) {
            case .getPage:
                return try getPage(id: arguments.pageId)
            case nil:
                return ToolResult([])
            }
        } catch {
            return ToolResult([error.localizedDescription])
        }
    }
}

private extension ConfluenceEngine {
    func getPage(id: String) throws -> ToolResult {
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else {
            throw ConfluenceError.invalidArgument("pageId must be a numeric string")
        }
        let base = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
        let url = "\(base)/rest/api/content/\(id)?expand=body.storage,version,space"
        let headers = [
            "Authorization": "Bearer \(config.authToken)",
            "Accept": "application/json"
        ]

        switch WebResponse<ConfluencePage>.withTimeout(30).get(url: url, headers: headers) {
        case .response(let page, _):
            let result = PageResult(
                id: page.id,
                title: page.title,
                space: page.space?.key,
                version: page.version?.number,
                body: page.body?.storage?.value ?? ""
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let text = (try? String(data: encoder.encode(result), encoding: .utf8))
                ?? "Could not serialize Confluence response"
            return ToolResult([text])
        case .failure(let error):
            throw ConfluenceError.requestFailed("\(error)")
        }
    }
}

private struct Arguments: Decodable {
    let pageId: String
}

private struct ConfluencePage: Decodable {
    struct Space: Decodable { let key: String }
    struct Version: Decodable { let number: Int }
    struct Body: Decodable {
        struct Storage: Decodable { let value: String }
        let storage: Storage?
    }

    let id: String
    let title: String
    let space: Space?
    let version: Version?
    let body: Body?
}

private struct PageResult: Encodable {
    let id: String
    let title: String
    let space: String?
    let version: Int?
    let body: String
}

private enum ConfluenceError: LocalizedError {
    case invalidArgument(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        case .requestFailed(let message): return "Confluence request failed: \(message)"
        }
    }
}
