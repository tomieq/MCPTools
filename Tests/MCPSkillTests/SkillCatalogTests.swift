import Foundation
import XCTest
@testable import MCPSkill

final class SkillCatalogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testParsesFrontmatter() throws {
        let skill = try XCTUnwrap(SkillParser.parse(
            markdown: """
            ---
            name: swift-http
            description: "Build HTTP servers"
            ---
            # Heading

            Body text.
            """,
            directoryURL: directory
        ))

        XCTAssertEqual(skill.name, "swift-http")
        XCTAssertEqual(skill.description, "Build HTTP servers")
        XCTAssertEqual(skill.content, "# Heading\n\nBody text.")
    }

    func testParsesFoldedDescription() throws {
        let skill = try XCTUnwrap(SkillParser.parse(
            markdown: "---\nname: a\ndescription: >\n  first line\n  second line\n---\nBody",
            directoryURL: directory
        ))

        XCTAssertEqual(skill.description, "first line second line")
    }

    func testFallsBackToFolderNameAndFirstParagraph() throws {
        let skill = try XCTUnwrap(SkillParser.parse(
            markdown: "# Title\n\nUse this for things.\n\nMore.",
            directoryURL: directory.appendingPathComponent("my-skill")
        ))

        XCTAssertEqual(skill.name, "my-skill")
        XCTAssertEqual(skill.description, "Use this for things.")
    }

    func testLoadsSkillsFromEntryPointAndSkipsFoldersWithoutSkillFile() throws {
        try writeSkill("alpha", markdown: "---\nname: alpha\ndescription: A\n---\nAlpha body")
        try writeSkill("beta", markdown: "Beta body")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("empty"),
            withIntermediateDirectories: true
        )

        let catalog = try SkillCatalog(skillPaths: [directory.path])

        XCTAssertEqual(catalog.skills.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(catalog.skill(named: "alpha")?.content, "Alpha body")
    }

    func testFirstSkillWinsOnNameCollision() throws {
        let second = directory.appendingPathComponent("second", isDirectory: true)
        try writeSkill("one", markdown: "---\nname: same\n---\nFirst")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try "---\nname: same\n---\nSecond".write(
            to: second.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let catalog = try SkillCatalog(skillPaths: [directory.appendingPathComponent("one").path, second.path])

        XCTAssertEqual(catalog.skills.count, 1)
        XCTAssertEqual(catalog.skills.first?.content, "First")
    }

    func testCreateStoresSkillInFirstPathAndRoundTrips() throws {
        let second = directory.appendingPathComponent("second", isDirectory: true)
        let first = directory.appendingPathComponent("first", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let catalog = try SkillCatalog(skillPaths: [first.path, second.path])
        let created = try catalog.create(name: "my-skill", description: "Says \"hi\": always", content: "# Do it\n\nSteps.")

        XCTAssertEqual(created.directoryURL.deletingLastPathComponent().lastPathComponent, "first")
        XCTAssertEqual(catalog.skill(named: "my-skill")?.description, "Says \"hi\": always")

        let reloaded = try SkillCatalog(skillPaths: [first.path])
        XCTAssertEqual(reloaded.skill(named: "my-skill")?.description, "Says \"hi\": always")
        XCTAssertEqual(reloaded.skill(named: "my-skill")?.content, "# Do it\n\nSteps.")
    }

    func testCreateRejectsDuplicatesAndInvalidNames() throws {
        try writeSkill("existing", markdown: "Body")
        let catalog = try SkillCatalog(skillPaths: [directory.path])

        XCTAssertThrowsError(try catalog.create(name: "existing", description: "d", content: "c"))
        XCTAssertThrowsError(try catalog.create(name: "../escape", description: "d", content: "c"))
        XCTAssertThrowsError(try catalog.create(name: ".hidden", description: "d", content: "c"))
        XCTAssertThrowsError(try catalog.create(name: "ok", description: " ", content: "c"))
        XCTAssertThrowsError(try catalog.create(name: "ok", description: "d", content: "  "))
    }

    func testThrowsForMissingPath() {
        XCTAssertThrowsError(try SkillCatalog(skillPaths: [directory.appendingPathComponent("missing").path]))
    }

    private func writeSkill(_ folder: String, markdown: String) throws {
        let skillDirectory = directory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try markdown.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
