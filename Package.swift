// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPTools",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MCPFileEditor", targets: ["MCPFileEditor"]),
        .library(name: "MCPGit", targets: ["MCPGit"]),
        .library(name: "MCPShell", targets: ["MCPShell"])
    ],
    dependencies: [
        .package(url: "https://github.com/tomieq/swifter", .upToNextMajor(from: "3.1.1")),
        .package(url: "https://github.com/tomieq/Logger", .upToNextMajor(from: "1.1.0")),
        .package(url: "https://github.com/tomieq/Env", .upToNextMajor(from: "1.0.8")),
        .package(url: "https://github.com/tomieq/MCPServer", branch: "master"),
        .package(url: "https://github.com/aus-der-Technik/FileMonitor.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "MCPFileEditor",
                dependencies: [
                    .product(name: "Swifter", package: "Swifter"),
                    .product(name: "Logger", package: "Logger"),
                    .product(name: "MCPServer", package: "MCPServer"),
                    .product(name: "FileMonitor", package: "FileMonitor")
                ]),
        .target(name: "MCPGit",
                dependencies: [
                    .product(name: "Logger", package: "Logger"),
                    .product(name: "MCPServer", package: "MCPServer")
                ]),
        .target(name: "MCPShell",
                dependencies: [
                    .product(name: "MCPServer", package: "MCPServer")
                ]),
        .executableTarget(
            name: "MCPFileEditorServer",
            dependencies: [
                .target(name: "MCPFileEditor"),
                .target(name: "MCPGit"),
                .target(name: "MCPShell"),
                .product(name: "Env", package: "Env")
            ]
        ),
        .testTarget(
            name: "MCPFileEditorTests",
            dependencies: ["MCPFileEditor"]
        )
    ],
    swiftLanguageModes: [.v5]
)
