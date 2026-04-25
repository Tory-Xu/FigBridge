import Foundation
import Testing
@testable import FigBridgeCore

struct BatchStoreIncrementalTests {
    @Test func updatesExistingBatchAndDeletesPersistedItemFiles() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        var initialItem = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let batch = GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root.path,
            mode: .sequential,
            items: [initialItem]
        )

        var persisted = try store.createBatch(batch)
        let yamlURL = persisted.itemDirectories[0].appendingPathComponent("generated.yaml")
        let outputURL = persisted.itemDirectories[0].appendingPathComponent("agent-output.txt")
        try "yaml".write(to: yamlURL, atomically: true, encoding: .utf8)
        try "output".write(to: outputURL, atomically: true, encoding: .utf8)
        initialItem.generatedYAMLPath = yamlURL.path
        initialItem.agentOutputPath = outputURL.path
        let appendedItem = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        persisted = try store.updateBatch(
            id: batch.id,
            sourceInputText: batch.sourceInputText,
            agent: batch.agent,
            promptSnapshot: batch.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: batch.outputDirectory, isDirectory: true),
            mode: batch.mode,
            items: [initialItem, appendedItem]
        )

        #expect(persisted.summary.items.count == 2)
        #expect(persisted.itemDirectories.count == 2)

        try store.deleteBatchItem(batchID: batch.id, itemID: initialItem.id)
        let rescanned = try #require(try store.loadBatch(id: batch.id))

        #expect(rescanned.summary.items.count == 1)
        #expect(rescanned.summary.items[0].id == appendedItem.id)
        #expect(!FileManager.default.fileExists(atPath: yamlURL.path))
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }
}
