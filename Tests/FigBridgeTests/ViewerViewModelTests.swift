import Foundation
import Testing
@testable import FigBridgeCore
@testable import FigBridgeApp

@MainActor
struct ViewerViewModelTests {
    @Test func reloadSelectsFirstBatchAndFirstItemAndLoadsYaml() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        _ = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)

        viewModel.reload()

        #expect(viewModel.selectedBatch?.summary.id == "batch-1")
        #expect(viewModel.selectedItem?.title == "Item A")
        #expect(viewModel.selectedYAMLText == "yaml-a")
        #expect(viewModel.selectedSourceInputText == "source-1")
    }

    @Test func switchingSelectedItemReloadsYamlText() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: "yaml-b")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        viewModel.selectedItemID = persisted.summary.items[1].id

        #expect(viewModel.selectedItem?.title == "Item B")
        #expect(viewModel.selectedYAMLText == "yaml-b")
    }

    @Test func switchingBatchSelectsFirstItemAndReloadsSourceAndYaml() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let newer = try makePersistedBatch(
            store: store,
            id: "batch-new",
            createdAt: Date(timeIntervalSince1970: 20),
            sourceInputText: "source-new",
            items: [
                makeItem(title: "New A", nodeId: "2:1", yamlText: "yaml-new-a"),
                makeItem(title: "New B", nodeId: "2:2", yamlText: "yaml-new-b")
            ]
        )
        let older = try makePersistedBatch(
            store: store,
            id: "batch-old",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-old",
            items: [
                makeItem(title: "Old A", nodeId: "1:1", yamlText: "yaml-old-a")
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        #expect(viewModel.selectedBatch?.summary.id == newer.summary.id)
        #expect(viewModel.selectedItem?.id == newer.summary.items[0].id)

        viewModel.selectedBatchID = older.summary.id

        #expect(viewModel.selectedBatch?.summary.id == older.summary.id)
        #expect(viewModel.selectedItem?.id == older.summary.items[0].id)
        #expect(viewModel.selectedYAMLText == "yaml-old-a")
        #expect(viewModel.selectedSourceInputText == "source-old")
    }

    @Test func selectingItemWithoutYamlClearsYamlText() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let persisted = try makePersistedBatch(
            store: store,
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 10),
            sourceInputText: "source-1",
            items: [
                makeItem(title: "Item A", nodeId: "1:1", yamlText: "yaml-a"),
                makeItem(title: "Item B", nodeId: "1:2", yamlText: nil)
            ]
        )

        let viewModel = ViewerViewModel(batchStore: store)
        viewModel.reload()

        viewModel.selectedItemID = persisted.summary.items[1].id

        #expect(viewModel.selectedItem?.title == "Item B")
        #expect(viewModel.selectedYAMLText == nil)
    }

    private func makePersistedBatch(
        store: BatchStore,
        id: String,
        createdAt: Date,
        sourceInputText: String,
        items: [FigmaLinkItem]
    ) throws -> PersistedBatch {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let batch = GenerationBatch(
            id: id,
            createdAt: createdAt,
            agent: .codex,
            promptSnapshot: "prompt",
            sourceInputText: sourceInputText,
            outputDirectory: store.rootDirectory.path,
            mode: .sequential,
            items: items
        )
        var persisted = try store.createBatch(batch)
        var updatedItems = persisted.summary.items

        for (index, itemDirectory) in persisted.itemDirectories.enumerated() {
            guard let yamlText = items[index].generatedYAMLPath else {
                continue
            }
            let yamlURL = itemDirectory.appendingPathComponent("generated.yaml")
            try yamlText.write(to: yamlURL, atomically: true, encoding: .utf8)
            updatedItems[index].generatedYAMLPath = yamlURL.path

            let metaURL = itemDirectory.appendingPathComponent("meta.json")
            try encoder.encode(updatedItems[index]).write(to: metaURL)
        }

        let updatedBatch = GenerationBatch(
            id: persisted.summary.id,
            createdAt: persisted.summary.createdAt,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            sourceInputText: persisted.summary.sourceInputText,
            outputDirectory: persisted.summary.outputDirectory,
            mode: persisted.summary.mode,
            items: updatedItems
        )
        let batchURL = persisted.batchDirectory.appendingPathComponent("batch.json")
        try encoder.encode(updatedBatch).write(to: batchURL)

        persisted = try #require(store.scanBatches().first(where: { $0.summary.id == id }))
        return persisted
    }

    private func makeItem(title: String, nodeId: String, yamlText: String?) -> FigmaLinkItem {
        let nodeIDForURL = nodeId.replacingOccurrences(of: ":", with: "-")
        var item = FigmaLinkItem(
            rawInputLine: title,
            title: title,
            url: "https://www.figma.com/design/FILE123/App?node-id=\(nodeIDForURL)",
            fileKey: "FILE123",
            nodeId: nodeId
        )
        item.generatedYAMLPath = yamlText
        return item
    }
}
