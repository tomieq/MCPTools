import Foundation
import MCPServer

struct ToolSuccess<Value: Encodable>: Encodable {
    let ok = true
    let data: Value
}

struct FileTreeResult: Encodable { let tree: String }
struct FilePathsResult: Encodable { let paths: [String] }
struct FileMoveResult: Encodable { let oldFilepath: String; let newFilepath: String }
struct FileWriteResult: Encodable { let filepath: String; let changed: Bool }
struct FileDeleteResult: Encodable { let filepath: String; let deleted: Bool }
struct SearchTextResult: Encodable { let results: [SearchResult]; let limit: Int; let truncated: Bool }
struct PatchToolResult: Encodable {
    let filesChanged: Int
    let changed: Bool
    let dryRun: Bool
    let paths: [String]
    let report: PatchDryRunReport
}

struct ToolResponseFactory {
    func success<Value: Encodable>(_ data: Value) -> ToolResult {
        response(ToolSuccess(data: data), fallback: "Could not serialize tool response")
    }

    func failure(_ error: Error, code: String = "operation_failed") -> ToolResult {
        ToolResult([error.localizedDescription])
    }

    func failure(_ message: String, code: String) -> ToolResult {
        failure(ToolResponseError(message: message), code: code)
    }

    private func response<Value: Encodable>(_ value: Value, fallback: String) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? String(data: encoder.encode(value), encoding: .utf8))
            ?? fallback
        return ToolResult([text])
    }
}

private struct ToolResponseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
