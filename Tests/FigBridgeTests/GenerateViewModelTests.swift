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
}

@MainActor
private struct GenerateViewModelHarness {
    let viewModel: GenerateViewModel
    let runner: RecordingAgentRunner

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
        let runner = RecordingAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let viewModel = GenerateViewModel(
            settingsViewModel: settingsViewModel,
            batchStore: batchStore,
            generationCoordinator: coordinator,
            figmaService: figmaService
        )

        self.viewModel = viewModel
        self.runner = runner

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
