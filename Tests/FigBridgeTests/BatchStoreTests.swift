import Foundation
import Testing
@testable import FigBridgeCore

struct BatchStoreTests {
    @Test func createsBatchStructureAndCanRescan() throws {
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
            items: [item]
        )

        let persisted = try store.createBatch(batch)
        let scanned = try store.scanBatches()

        #expect(FileManager.default.fileExists(atPath: persisted.batchDirectory.appendingPathComponent("batch.json").path))
        #expect(FileManager.default.fileExists(atPath: persisted.itemDirectories[0].appendingPathComponent("meta.json").path))
        #expect(scanned.count == 1)
        #expect(scanned[0].summary.items.count == 1)
    }

    @Test func copiesPromptFromExistingYamlOnly() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        var item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE123/App?node-id=1-2",
            fileKey: "FILE123",
            nodeId: "1:2"
        )
        item.generatedYAMLPath = "/tmp/a.yaml"
        let prompt = store.makeCopyPrompt(for: [item])

        #expect(prompt.contains("Implement this design from yaml files."))
        #expect(prompt.contains("/tmp/a.yaml"))
    }
}
