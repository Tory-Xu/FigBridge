import Foundation
import Testing
@testable import FigBridgeCore

struct BatchImportExportTests {
    @Test func exportsBatchAsZipAndImportsDirectoryWithRename() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let batch = GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let zipURL = sandbox.root.appendingPathComponent("batch-1.zip")
        try store.exportBatch(at: persisted.batchDirectory, to: zipURL)

        #expect(FileManager.default.fileExists(atPath: zipURL.path))

        let importedURL = try store.importBatchDirectory(from: persisted.batchDirectory)
        let importedAgainURL = try store.importBatchDirectory(from: persisted.batchDirectory)

        #expect(importedURL.lastPathComponent == "batch-1(2)")
        #expect(importedAgainURL.lastPathComponent == "batch-1(3)")

        let importedBatch = try #require(try store.loadBatch(id: "batch-1(2)"))
        #expect(importedBatch.summary.id == "batch-1(2)")

        let importedBatchJSON = try String(contentsOf: importedURL.appendingPathComponent("batch.json"), encoding: .utf8)
        #expect(importedBatchJSON.contains("\"id\" : \"batch-1(2)\""))
    }

    @Test func importsDirectoryWhenRootDirectoryDoesNotExist() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let sourceStore = BatchStore(rootDirectory: sandbox.root.appendingPathComponent("source-store"))
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        let batch = GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )
        let persisted = try sourceStore.createBatch(batch)

        let importRoot = sandbox.root.appendingPathComponent("fresh-store")
        let importStore = BatchStore(rootDirectory: importRoot)

        let importedURL = try importStore.importBatchDirectory(from: persisted.batchDirectory)

        #expect(FileManager.default.fileExists(atPath: importRoot.path))
        #expect(importedURL.lastPathComponent == "batch-1")
        let importedBatch = try #require(try importStore.loadBatch(id: "batch-1"))
        #expect(importedBatch.summary.id == "batch-1")
    }
}
