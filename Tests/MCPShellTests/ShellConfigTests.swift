import Foundation
import XCTest
@testable import MCPShell

final class ShellConfigTests: XCTestCase {
    func testDecodesWithAdditionalPathEntries() throws {
        let json = Data(#"{"projectPath": "/tmp/project", "additionalPathEntries": ["/opt/tools/bin", "/usr/local/bin"]}"#.utf8)

        let config = try JSONDecoder().decode(ShellConfig.self, from: json)

        XCTAssertEqual(config.projectPath, "/tmp/project")
        XCTAssertEqual(config.additionalPathEntries, ["/opt/tools/bin", "/usr/local/bin"])
    }

    func testAdditionalPathEntriesDefaultsToEmpty() throws {
        let json = Data(#"{"projectPath": "/tmp/project"}"#.utf8)

        let config = try JSONDecoder().decode(ShellConfig.self, from: json)

        XCTAssertEqual(config.additionalPathEntries, [])
    }
}

final class ShellPathTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeEngine(additionalPathEntries: [String]) throws -> ShellEngine {
        try ShellEngine(
            projectDirectory: ShellProjectDirectory(projectPath: directory.path),
            additionalPathEntries: additionalPathEntries
        )
    }

    func testPrependsAdditionalEntriesBeforeInheritedPath() throws {
        let engine = try makeEngine(additionalPathEntries: ["/opt/tools/bin", "/usr/local/bin"])
        var environment = ["PATH": "/usr/bin:/bin"]

        engine.prependAdditionalPathEntries(to: &environment)

        XCTAssertEqual(environment["PATH"], "/opt/tools/bin:/usr/local/bin:/usr/bin:/bin")
    }

    func testPreservesOrderOfMultipleAdditionalEntries() throws {
        let engine = try makeEngine(additionalPathEntries: ["/b", "/a"])
        var environment: [String: String] = [:]

        engine.prependAdditionalPathEntries(to: &environment)

        XCTAssertEqual(environment["PATH"], "/b:/a")
    }

    func testSetsPathWhenInheritedIsMissing() throws {
        let engine = try makeEngine(additionalPathEntries: ["/opt/tools/bin"])
        var environment: [String: String] = [:]

        engine.prependAdditionalPathEntries(to: &environment)

        XCTAssertEqual(environment["PATH"], "/opt/tools/bin")
    }

    func testSetsPathWhenInheritedIsEmpty() throws {
        let engine = try makeEngine(additionalPathEntries: ["/opt/tools/bin"])
        var environment = ["PATH": ""]

        engine.prependAdditionalPathEntries(to: &environment)

        XCTAssertEqual(environment["PATH"], "/opt/tools/bin")
    }

    func testEmptyAdditionalEntriesLeaveEnvironmentUnchanged() throws {
        let engine = try makeEngine(additionalPathEntries: [])
        var environment = ["PATH": "/usr/bin:/bin"]

        engine.prependAdditionalPathEntries(to: &environment)

        XCTAssertEqual(environment["PATH"], "/usr/bin:/bin")
    }

    func testRejectsRelativeAdditionalPathEntry() {
        let config = ShellConfig(projectPath: directory.path, additionalPathEntries: ["relative/path"])

        XCTAssertThrowsError(try MCPShell(config: config)) { error in
            XCTAssertTrue(error is ShellConfigurationError)
        }
    }

    func testRejectsEmptyAdditionalPathEntry() {
        let config = ShellConfig(projectPath: directory.path, additionalPathEntries: [""])

        XCTAssertThrowsError(try MCPShell(config: config)) { error in
            XCTAssertTrue(error is ShellConfigurationError)
        }
    }

    func testAcceptsValidAdditionalPathEntries() throws {
        let config = ShellConfig(projectPath: directory.path, additionalPathEntries: ["/opt/tools/bin"])

        XCTAssertNoThrow(try MCPShell(config: config))
    }
}
