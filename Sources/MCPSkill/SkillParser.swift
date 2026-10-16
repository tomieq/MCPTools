import Foundation

enum SkillParser {
    /// Parses a SKILL.md file. Frontmatter is optional; a missing name falls back to the folder name
    /// and a missing description to the first paragraph.
    static func parse(markdown: String, directoryURL: URL) -> Skill? {
        let (metadata, body) = splitFrontmatter(markdown)
        let content = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let name = nonEmpty(metadata["name"]) ?? directoryURL.lastPathComponent
        let description = nonEmpty(metadata["description"]) ?? firstParagraph(of: content)
        return Skill(name: name, description: description, content: content, directoryURL: directoryURL)
    }

    private static func splitFrontmatter(_ markdown: String) -> ([String: String], String) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([:], markdown)
        }

        let body = lines[(end + 1)...].joined(separator: "\n")
        return (parseKeyValues(Array(lines[1..<end])), body)
    }

    private static func parseKeyValues(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"),
                  let colon = line.firstIndex(of: ":") else {
                continue
            }

            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            // Block scalars (`>`, `|`) and plain multi-line values continue on indented lines.
            var continuation: [String] = []
            while index < lines.count, lines[index].hasPrefix(" ") || lines[index].hasPrefix("\t") || lines[index].isEmpty {
                continuation.append(lines[index].trimmingCharacters(in: .whitespaces))
                index += 1
            }
            if [">", "|", ">-", "|-"].contains(value) {
                value = ""
            }
            let parts = ([value] + continuation).filter { !$0.isEmpty }
            result[key] = unquote(parts.joined(separator: " "))
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first, let last = value.last,
              first == last, first == "\"" || first == "'" else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        guard first == "\"" else { return inner }
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func firstParagraph(of content: String) -> String {
        let paragraph = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            ?? ""
        let text = paragraph.replacingOccurrences(of: "\n", with: " ")
        return text.count > 300 ? "\(text.prefix(300))…" : text
    }
}
