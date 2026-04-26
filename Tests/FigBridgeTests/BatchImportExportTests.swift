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
        _ = try store.exportBatch(at: persisted.batchDirectory, to: zipURL)

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

    @Test func exportsAndImportsBatchWithPreviewAndResourceAssets() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root.appendingPathComponent("store"))
        let itemID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
        let batchDirectory = store.rootDirectory.appendingPathComponent("batch-assets", isDirectory: true)
        let itemDirectory = batchDirectory.appendingPathComponent("items/\(itemID.uuidString.lowercased())-1-2", isDirectory: true)
        let yamlDirectory = itemDirectory.appendingPathComponent("yaml", isDirectory: true)
        let assetsDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        let exportsDirectory = batchDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: yamlDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let previewURL = assetsDirectory.appendingPathComponent("preview.png")
        let resourceURL = assetsDirectory.appendingPathComponent("1-img-ref-1.png")
        let yamlURL = yamlDirectory.appendingPathComponent("figma-node-1-2.yaml")
        try Data("preview".utf8).write(to: previewURL)
        try Data("resource".utf8).write(to: resourceURL)
        try "yaml".write(to: yamlURL, atomically: true, encoding: .utf8)

        let item = FigmaLinkItem(
            id: itemID,
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2",
            previewStatus: .success,
            resourceStatus: .success,
            previewImagePath: previewURL.path,
            resourceItems: [
                FigmaResourceItem(
                    name: "img-ref-1",
                    kind: .image,
                    format: .png,
                    remoteURL: "https://cdn.example/image.png",
                    localPath: resourceURL.path
                )
            ],
            generationStatus: .success,
            generatedYAMLPath: yamlURL.path
        )

        let batch = GenerationBatch(
            id: "batch-assets",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: exportsDirectory.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let zipURL = sandbox.root.appendingPathComponent("batch-assets.zip")
        _ = try store.exportBatch(at: persisted.batchDirectory, to: zipURL)

        let importedURL = try store.importBatchArchive(from: zipURL)
        let importedBatch = try #require(try store.loadBatch(id: importedURL.lastPathComponent))
        let importedItem = try #require(importedBatch.summary.items.first)
        let importedPreviewPath = try #require(importedItem.previewImagePath)
        let importedResourcePath = try #require(importedItem.resourceItems.first?.localPath)

        #expect(FileManager.default.fileExists(atPath: importedPreviewPath))
        #expect(FileManager.default.fileExists(atPath: importedResourcePath))
        #expect(importedPreviewPath.hasPrefix(importedURL.path))
        #expect(importedResourcePath.hasPrefix(importedURL.path))
    }

    @Test func exportBatchReportsMissingImageAssetsWithoutFailing() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root.appendingPathComponent("store"))
        let itemID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
        let batchDirectory = store.rootDirectory.appendingPathComponent("batch-missing-assets", isDirectory: true)
        let itemDirectory = batchDirectory.appendingPathComponent("items/\(itemID.uuidString.lowercased())-1-2", isDirectory: true)
        let assetsDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        let exportsDirectory = batchDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let previewURL = assetsDirectory.appendingPathComponent("preview.png")
        try Data("preview".utf8).write(to: previewURL)

        let missingResourceURL = assetsDirectory.appendingPathComponent("missing.png")
        let item = FigmaLinkItem(
            id: itemID,
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2",
            previewStatus: .success,
            resourceStatus: .success,
            previewImagePath: previewURL.path,
            resourceItems: [
                FigmaResourceItem(
                    name: "missing",
                    kind: .image,
                    format: .png,
                    remoteURL: "https://cdn.example/image.png",
                    localPath: missingResourceURL.path
                )
            ]
        )

        let batch = GenerationBatch(
            id: "batch-missing-assets",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: exportsDirectory.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let zipURL = sandbox.root.appendingPathComponent("batch-missing-assets.zip")
        let result = try store.exportBatch(at: persisted.batchDirectory, to: zipURL)

        #expect(FileManager.default.fileExists(atPath: zipURL.path))
        #expect(result.missingPreviewPaths.isEmpty)
        #expect(result.missingResourcePaths == [missingResourceURL.path])
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
