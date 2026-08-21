//
//  MCPFileEditor.swift
//  MCPFileEditor
//
//  Created by: tomieq on 29/07/2026
//
import MCPServer
import Swifter

public final class MCPFileEditor {
    let config: FolderConfig
    let folder: Folder
    let fileCache: FileCache
    var folderMonitor: FolderMonitor?
    public let mcp: MCPServer

    public init(config: FolderConfig,
                server: HttpServer? = nil) throws {
        self.config = config
        self.folder = Folder(config: config)
        self.fileCache = FileCache(folder: folder)
        let config = MCPServerConfig(
            serverName: "MCP File Editor",
            engines: [
                CoderEngine(folder: folder, cache: fileCache)
            ]
        )
        self.mcp = MCPServer(config: config, server: server)
        self.folderMonitor = try FolderMonitor(folder: folder.realUrl) { [unowned self] change in
            fileCache.fileChanged(change)
        }
    }
}
