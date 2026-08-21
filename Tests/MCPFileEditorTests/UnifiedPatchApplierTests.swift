import Foundation
import XCTest
@testable import MCPFileEditor

final class UnifiedPatchApplierTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAppliesUpdateAndCreatesNestedFile() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "one\ntwo\n".write(to: existing, atomically: true, encoding: .utf8)

        let patch = """
        diff --git a/example.txt b/example.txt
        --- a/example.txt
        +++ b/example.txt
        @@ -1,2 +1,3 @@
         one
        -two
        +two changed
        +three
        --- /dev/null
        +++ b/nested/new.txt
        @@ -0,0 +1 @@
        +created
        """

        let result = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(result.filesChanged, 2)
        XCTAssertEqual(try String(contentsOf: existing), "one\ntwo changed\nthree\n")
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("nested/new.txt")), "created\n")
    }

    func testDryRunAndMismatchedHunkDoNotWrite() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "one\n".write(to: existing, atomically: true, encoding: .utf8)
        let applier = UnifiedPatchApplier(rootURL: directory)

        let validPatch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1 +1 @@
        -one
        +two
        """
        _ = try applier.apply(validPatch, dryRun: true)
        XCTAssertEqual(try String(contentsOf: existing), "one\n")

        let invalidPatch = validPatch.replacingOccurrences(of: "-one", with: "-missing")
        XCTAssertThrowsError(try applier.apply(invalidPatch, dryRun: false))
        XCTAssertEqual(try String(contentsOf: existing), "one\n")
    }

    func testAppliesRangeLessContextPatch() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "before\nold value\nafter\n".write(to: existing, atomically: true, encoding: .utf8)

        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@
        -old value
        +new value
        """

        _ = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(try String(contentsOf: existing), "before\nnew value\nafter\n")
    }

    func testFindsAUniqueHunkWhenItsLineRangeIsOffset() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "inserted\nbefore\nold value\nafter\n".write(to: existing, atomically: true, encoding: .utf8)

        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -2,3 +2,3 @@
         before
        -old value
        +new value
         after
        """

        _ = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(try String(contentsOf: existing), "inserted\nbefore\nnew value\nafter\n")
    }

    func testReportsHeaderCountMismatchesClearly() throws {
        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1,2 +1,2 @@
        -old value
        +new value
        """

        XCTAssertThrowsError(try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Hunk header count mismatch"))
        }
    }

    func testAppliesWhitespaceInsensitiveContext() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "\told value\n".write(to: existing, atomically: true, encoding: .utf8)
        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1 +1 @@
        -    old value
        +new value
        """

        _ = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(try String(contentsOf: existing), "new value\n")
    }

    func testDryRunReturnsStructuredMatchMetadata() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "old value\n".write(to: existing, atomically: true, encoding: .utf8)
        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1 +1 @@
        -old value
        +new value
        """

        let result = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: true)
        let json = try JSONSerialization.jsonObject(with: try XCTUnwrap(result.structuredMessage.data(using: .utf8))) as? [String: Any]
        let files = try XCTUnwrap(json?["files"] as? [[String: Any]])
        let file = try XCTUnwrap(files.first)
        let hunks = try XCTUnwrap(file["hunks"] as? [[String: Any]])

        XCTAssertEqual(file["path"] as? String, "example.txt")
        XCTAssertEqual(file["additions"] as? Int, 1)
        XCTAssertEqual(file["removals"] as? Int, 1)
        XCTAssertEqual(hunks.first?["matchedLine"] as? Int, 1)
        XCTAssertEqual(hunks.first?["matchingStrategy"] as? String, "header-line")
        XCTAssertEqual(try String(contentsOf: existing), "old value\n")
    }

    func testTextReplacementRequiresAnExactMatchCount() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "old value\nold value\n".write(to: existing, atomically: true, encoding: .utf8)
        let replacer = TextReplacer(rootURL: directory)

        XCTAssertThrowsError(try replacer.replace(filepath: "example.txt",
                                                  find: "old value",
                                                  replacement: "new value",
                                                  expectedMatches: 1,
                                                  replaceAll: false,
                                                  dryRun: false))
        XCTAssertEqual(try String(contentsOf: existing), "old value\nold value\n")
    }

    func testTextReplacementCanReplaceAllVerifiedMatches() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "old value\nold value\n".write(to: existing, atomically: true, encoding: .utf8)

        let result = try TextReplacer(rootURL: directory).replace(filepath: "example.txt",
                                                                  find: "old value",
                                                                  replacement: "new value",
                                                                  expectedMatches: 2,
                                                                  replaceAll: true,
                                                                  dryRun: false)

        XCTAssertEqual(result.matches, 2)
        XCTAssertEqual(result.replacements, 2)
        XCTAssertEqual(try String(contentsOf: existing), "new value\nnew value\n")
    }

    func testProjectWideReplacementValidatesEveryCachedTargetBeforeWriting() throws {
        let first = directory.appendingPathComponent("first.txt")
        let second = directory.appendingPathComponent("second.txt")
        try "old value\n".write(to: first, atomically: true, encoding: .utf8)
        try "old value\n".write(to: second, atomically: true, encoding: .utf8)

        let folder = Folder(config: .init(projectPath: directory.path, fileExtensions: "txt"))
        let cache = FileCache(folder: folder)
        try "changed externally\n".write(to: second, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try TextReplacer(rootURL: directory).replaceAll(
            targets: cache.replacementTargets("old value"),
            find: "old value",
            replacement: "new value",
            expectedMatches: 2,
            dryRun: false
        ))
        XCTAssertEqual(try String(contentsOf: first), "old value\n")
        XCTAssertEqual(try String(contentsOf: second), "changed externally\n")
    }

    func testProjectPathResolutionRejectsTraversalAndAbsolutePaths() throws {
        let folder = Folder(config: .init(projectPath: directory.path, fileExtensions: "txt"))

        XCTAssertThrowsError(try folder.projectURL(for: "../outside.txt"))
        XCTAssertThrowsError(try folder.projectURL(for: "/tmp/outside.txt"))
        XCTAssertThrowsError(try folder.projectURL(for: "nested/../../outside.txt"))
    }

    func testProjectPathResolutionRejectsSymlinkEscapes() throws {
        let folder = Folder(config: .init(projectPath: directory.path, fileExtensions: "txt"))
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDirectory) }

        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("external"),
            withDestinationURL: externalDirectory
        )

        XCTAssertThrowsError(try folder.projectURL(for: "external/outside.txt"))
    }

    func testFolderIncludesExplicitlyAllowedExtensionlessFiles() throws {
        try "pipeline".write(to: directory.appendingPathComponent("Jenkinsfile"), atomically: true, encoding: .utf8)
        try "ignore".write(to: directory.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try "source".write(to: directory.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let folder = Folder(config: .init(projectPath: directory.path, fileExtensions: "swift,Jenkinsfile"))

        XCTAssertTrue(folder.files().contains("Jenkinsfile"))
        XCTAssertTrue(folder.files().contains("main.swift"))
        XCTAssertFalse(folder.files().contains("README"))
        XCTAssertTrue(folder.tree().contains("Jenkinsfile"))
        XCTAssertFalse(folder.tree().contains("README"))
    }

    func testFileReaderBoundsLinesAndBytes() throws {
        let file = directory.appendingPathComponent("example.txt")
        try "one\ntwo\nthree\nfour\n".write(to: file, atomically: true, encoding: .utf8)

        let result = try FileReader().read(url: file,
                                           filepath: "example.txt",
                                           startLine: 2,
                                           endLine: 4,
                                           maxBytes: 7)

        XCTAssertEqual(result.content, "two\nthr")
        XCTAssertEqual(result.startLine, 2)
        XCTAssertEqual(result.endLine, 4)
        XCTAssertEqual(result.totalLines, 4)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.nextStartLine, 2)
    }

    func testFileInspectorReportsMetadataAndHash() throws {
        let file = directory.appendingPathComponent("example.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)

        let metadata = try FileInspector().inspect(url: file, filepath: "example.txt", includeHash: true)

        XCTAssertTrue(metadata.exists)
        XCTAssertEqual(metadata.type, "file")
        XCTAssertEqual(metadata.byteSize, 6)
        XCTAssertEqual(metadata.encoding, "utf-8")
        XCTAssertEqual(metadata.isBinary, false)
        XCTAssertEqual(metadata.sha256, "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
    }

    func testSearchSupportsCaseGlobsAndContext() throws {
        try "first\nNeedle value\nthird\n".write(to: directory.appendingPathComponent("include.txt"), atomically: true, encoding: .utf8)
        try "needle ignored\n".write(to: directory.appendingPathComponent("exclude.txt"), atomically: true, encoding: .utf8)
        let folder = Folder(config: .init(projectPath: directory.path, fileExtensions: "txt"))
        let cache = FileCache(folder: folder)
        let options = SearchOptions(query: "needle",
                                    useRegex: false,
                                    caseSensitive: false,
                                    includeGlobs: ["include.*"],
                                    excludeGlobs: [],
                                    limit: 10,
                                    contextLines: 1)

        let results = try cache.matching(options).results

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].filepath, "include.txt")
        XCTAssertEqual(results[0].line, 2)
        XCTAssertEqual(results[0].contextBefore, ["first"])
        XCTAssertEqual(results[0].contextAfter, ["third"])
    }
}

extension UnifiedPatchApplierTests {
    func testResponsesArePlainText() throws {
        let payload = FileTreeResult(tree: "example")
        let responses = ToolResponseFactory()

        let success = try jsonObject(responses.success(payload))
        XCTAssertNil(success["structuredContent"])
        XCTAssertEqual(try textContent(success), ["{\"data\":{\"tree\":\"example\"},\"ok\":true}"])

        let failure = try jsonObject(responses.failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed"])))
        XCTAssertNil(failure["structuredContent"])
        XCTAssertEqual(try textContent(failure), ["Failed"])
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func textContent(_ value: [String: Any]) throws -> [String] {
        try XCTUnwrap(value["content"] as? [[String: String]]).compactMap { $0["text"] }
    }
}
