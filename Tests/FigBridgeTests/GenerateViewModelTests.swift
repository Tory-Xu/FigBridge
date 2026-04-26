import Foundation
import Testing
@testable import FigBridgeCore
@testable import FigBridgeApp

@MainActor
struct GenerateViewModelTests {
    @Test func multipleGenerationsReuseSameBatchUntilReset() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [first]
        await harness.viewModel.generate()
        let initialBatchID = try #require(harness.viewModel.currentBatchID)

        harness.viewModel.items.append(second)
        await harness.viewModel.generate()

        #expect(harness.viewModel.currentBatchID == initialBatchID)
        #expect(await harness.runner.recordedCalls() == ["FILE1|1:2", "FILE2|3:4"])
        #expect(harness.viewModel.processedItems.count == 2)

        harness.viewModel.resetWorkspace()
        #expect(harness.viewModel.currentBatchID == nil)
        #expect(harness.viewModel.currentBatchDirectory == nil)
    }

    @Test func pendingAndProcessedItemsAreDerivedFromYamlPresence() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        var processed = FigmaLinkItem(rawInputLine: "done", title: "Done", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        processed.generatedYAMLPath = "/tmp/generated.yaml"
        let pending = FigmaLinkItem(rawInputLine: "todo", title: "Todo", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [processed, pending]

        #expect(harness.viewModel.processedItems.map(\.id) == [processed.id])
        #expect(harness.viewModel.pendingItems.map(\.id) == [pending.id])
        #expect(harness.viewModel.canGenerate)
    }

    @Test func deletingSelectedItemUpdatesSelectionAndGenerationAvailability() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        harness.viewModel.items = [first, second]
        harness.viewModel.selectedItemID = first.id
        harness.viewModel.deleteItem(id: first.id)

        #expect(harness.viewModel.items.map(\.id) == [second.id])
        #expect(harness.viewModel.selectedItemID == second.id)

        harness.viewModel.deleteItem(id: second.id)

        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.selectedItemID == nil)
        #expect(!harness.viewModel.canGenerate)
    }

    @Test func addInputShowsHintForEmptyTextAndClearsTextAfterSuccess() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.inputText = "   \n  "
        harness.viewModel.addInput()

        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.validationMessage == "请输入要添加的信息")

        harness.viewModel.inputText = "首页: @https://www.figma.com/design/FILE1/A?node-id=1-2"
        harness.viewModel.addInput()

        #expect(harness.viewModel.items.count == 1)
        #expect(harness.viewModel.inputText.isEmpty)
    }

    @Test func renameSelectedItemPersistsToCurrentBatchAndLoadsYamlText() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(rawInputLine: "one", title: "Old", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        harness.viewModel.items = [item]
        await harness.viewModel.generate()
        let generatedItem = try #require(harness.viewModel.items.first)
        harness.viewModel.selectedItemID = generatedItem.id
        await harness.viewModel.loadSelectedItemPreviewIfNeeded()

        #expect(harness.viewModel.selectedYAMLText == "name: 1:2")

        harness.viewModel.beginRenamingSelectedItem()
        harness.viewModel.renamingTitle = "Renamed"
        harness.viewModel.commitRename()

        #expect(harness.viewModel.items.first?.title == "Renamed")

        let currentBatchID = try #require(harness.viewModel.currentBatchID)
        let persisted = try #require(try harness.batchStore.loadBatch(id: currentBatchID))
        #expect(persisted.summary.items.first?.title == "Renamed")
    }

    @Test func bootstrapRestoresSavedWorkspaceDraft() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        let draft = GenerateWorkspaceDraft(
            selectedAgentID: AgentProvider.codex.id,
            promptTemplate: "draft prompt",
            outputDirectoryPath: sandbox.root.appendingPathComponent("exports", isDirectory: true).path,
            mode: .parallel,
            parallelism: 4,
            inputText: "draft input",
            items: [item],
            selectedItemID: item.id,
            currentBatchID: "batch-draft",
            currentBatchDirectory: sandbox.root.appendingPathComponent("batch-draft", isDirectory: true).path
        )
        try harness.draftStore.save(draft)

        let restoredHarness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        await restoredHarness.viewModel.bootstrap()

        #expect(restoredHarness.viewModel.selectedAgentID == AgentProvider.codex.id)
        #expect(restoredHarness.viewModel.promptTemplate == "draft prompt")
        #expect(restoredHarness.viewModel.outputDirectoryPath == draft.outputDirectoryPath)
        #expect(restoredHarness.viewModel.mode == .parallel)
        #expect(restoredHarness.viewModel.parallelism == 4)
        #expect(restoredHarness.viewModel.inputText == "draft input")
        #expect(restoredHarness.viewModel.items == [item])
        #expect(restoredHarness.viewModel.selectedItemID == item.id)
        #expect(restoredHarness.viewModel.currentBatchID == "batch-draft")
        #expect(restoredHarness.viewModel.currentBatchDirectory == draft.currentBatchDirectory)
    }

    @Test func newBatchClearsWorkspaceAndPersistsEmptyDraft() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        harness.viewModel.inputText = "pending input"
        harness.viewModel.items = [
            FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        ]
        harness.viewModel.currentBatchID = "batch-1"
        harness.viewModel.currentBatchDirectory = sandbox.root.appendingPathComponent("batch-1", isDirectory: true).path

        harness.viewModel.startNewBatch()

        #expect(harness.viewModel.inputText.isEmpty)
        #expect(harness.viewModel.items.isEmpty)
        #expect(harness.viewModel.selectedItemID == nil)
        #expect(harness.viewModel.currentBatchID == nil)
        #expect(harness.viewModel.currentBatchDirectory == nil)

        let draft = try #require(harness.draftStore.load())
        #expect(draft.inputText.isEmpty)
        #expect(draft.items.isEmpty)
        #expect(draft.currentBatchID == nil)
        #expect(draft.currentBatchDirectory == nil)
    }

    @Test func loadingExistingBatchIntoWorkspaceRestoresEditableContext() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let item = FigmaLinkItem(
            rawInputLine: "首页",
            title: "首页",
            url: "https://www.figma.com/design/FILE1/A?node-id=1-2",
            fileKey: "FILE1",
            nodeId: "1:2"
        )
        let persisted = try harness.batchStore.createBatch(GenerationBatch(
            id: "batch-1",
            createdAt: Date(timeIntervalSince1970: 0),
            agent: .codex,
            promptSnapshot: "batch prompt",
            sourceInputText: "batch input",
            outputDirectory: sandbox.root.path,
            mode: .parallel,
            parallelism: 5,
            items: [item]
        ))

        harness.viewModel.loadBatchIntoWorkspace(persisted)

        #expect(harness.viewModel.currentBatchID == "batch-1")
        #expect(harness.viewModel.currentBatchDirectory == persisted.batchDirectory.path)
        #expect(harness.viewModel.promptTemplate == "batch prompt")
        #expect(harness.viewModel.inputText == "batch input")
        #expect(harness.viewModel.mode == .parallel)
        #expect(harness.viewModel.parallelism == 5)
        #expect(harness.viewModel.items == [item])

        let draft = try #require(harness.draftStore.load())
        #expect(draft.currentBatchID == "batch-1")
        #expect(draft.parallelism == 5)
    }
}

@MainActor
private struct GenerateViewModelHarness {
    let viewModel: GenerateViewModel
    let runner: RecordingAgentRunner
    let batchStore: BatchStore
    let draftStore: GenerateWorkspaceDraftStore

    init(rootDirectory: URL) throws {
        let settingsStore = SettingsStore(fileURL: rootDirectory.appendingPathComponent("settings.json"))
        try settingsStore.save(AppSettings(
            selectedAgentID: AgentProvider.codex.id,
            promptTemplate: "prompt",
            outputDirectoryPath: rootDirectory.path,
            figmaToken: "",
            defaultExportFormat: .png,
            defaultGenerationMode: .sequential,
            parallelism: 2
        ))
        let agentService = AgentService(shellClient: ShellClient(environment: [:]))
        let figmaService = FigmaService(baseDirectory: rootDirectory)
        let settingsViewModel = SettingsViewModel(settingsStore: settingsStore, agentService: agentService, figmaService: figmaService)
        let batchStore = BatchStore(rootDirectory: rootDirectory)
        let draftStore = GenerateWorkspaceDraftStore(fileURL: rootDirectory.appendingPathComponent("generate-workspace-draft.json"))
        let runner = RecordingAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let viewModel = GenerateViewModel(
            settingsViewModel: settingsViewModel,
            batchStore: batchStore,
            generationCoordinator: coordinator,
            figmaService: figmaService,
            draftStore: draftStore
        )

        self.viewModel = viewModel
        self.runner = runner
        self.batchStore = batchStore
        self.draftStore = draftStore

        viewModel.availableAgents = [AgentDescriptor(provider: .codex, path: "/mock/codex", version: "1.0")]
        viewModel.selectedAgentID = AgentProvider.codex.id
        viewModel.promptTemplate = "prompt"
        viewModel.outputDirectoryPath = rootDirectory.path
        viewModel.mode = GenerationMode.sequential
        viewModel.parallelism = 2
    }
}

private actor RecordingAgentRunner: AgentRunning {
    private var calls: [String] = []

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> AgentRunResult {
        calls.append("\(item.fileKey)|\(item.nodeId)")
        return AgentRunResult(output: "name: \(item.nodeId)", executablePath: "/mock/\(provider.rawValue)", arguments: [])
    }

    func recordedCalls() -> [String] {
        calls
    }
}
