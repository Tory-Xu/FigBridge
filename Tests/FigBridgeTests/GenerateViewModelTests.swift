import Foundation
import Testing
@testable import FigBridgeCore
@testable import FigBridgeApp

@MainActor
struct GenerateViewModelTests {
    @Test func addInputPreloadsResourcesForAllNewItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let transport = MockFigmaTransport(responses: [
            MockHTTPResponse(
                path: "/v1/files/FILE1/nodes",
                query: ["ids": "1:2"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Node 1",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-1" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE1",
                query: ["ids": "1:2", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"1:2":"https://cdn.figma.test/preview-1.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE1/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/resource-1.png"}}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE2/nodes",
                query: ["ids": "3:4"],
                statusCode: 200,
                body: """
                {
                  "nodes": {
                    "3:4": {
                      "document": {
                        "id": "3:4",
                        "name": "Node 2",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-2" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            ),
            MockHTTPResponse(
                path: "/v1/images/FILE2",
                query: ["ids": "3:4", "format": "png", "scale": "2"],
                statusCode: 200,
                body: #"{"images":{"3:4":"https://cdn.figma.test/preview-2.png"}}"#
            ),
            MockHTTPResponse(
                path: "/v1/files/FILE2/images",
                query: [:],
                statusCode: 200,
                body: #"{"meta":{"images":{"img-ref-2":"https://cdn.figma.test/resource-2.png"}}}"#
            ),
            MockHTTPResponse(url: "https://cdn.figma.test/preview-1.png", statusCode: 200, data: Data("PNG1".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/resource-1.png", statusCode: 200, data: Data("RES1".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/preview-2.png", statusCode: 200, data: Data("PNG2".utf8)),
            MockHTTPResponse(url: "https://cdn.figma.test/resource-2.png", statusCode: 200, data: Data("RES2".utf8)),
        ])
        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            figmaTransport: transport,
            figmaToken: "token"
        )

        harness.viewModel.inputText = """
        首页: @https://www.figma.com/design/FILE1/App?node-id=1-2
        列表: @https://www.figma.com/design/FILE2/App?node-id=3-4
        """
        harness.viewModel.addInput()

        let loaded = await waitUntil {
            harness.viewModel.items.count == 2
            && harness.viewModel.items.allSatisfy { $0.previewStatus == .success && $0.resourceStatus == .success }
        }
        #expect(loaded)

        let requests = await transport.recordedRequests()
        #expect(requests.contains { $0.path == "/v1/files/FILE1/nodes" })
        #expect(requests.contains { $0.path == "/v1/files/FILE2/nodes" })
    }

    @Test func reloadResourcesRetriesOnlyFailedItem() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let transport = FlakyFileImagesTransport()
        let harness = try GenerateViewModelHarness(
            rootDirectory: sandbox.root,
            figmaTransport: transport,
            figmaToken: "token"
        )

        harness.viewModel.inputText = "首页: @https://www.figma.com/design/FILE1/App?node-id=1-2"
        harness.viewModel.addInput()

        let failed = await waitUntil {
            harness.viewModel.items.first?.resourceStatus == .failed
        }
        #expect(failed)
        let itemID = try #require(harness.viewModel.items.first?.id)

        harness.viewModel.reloadResources(for: itemID)

        let recovered = await waitUntil {
            harness.viewModel.items.first?.resourceStatus == .success
            && harness.viewModel.items.first?.previewStatus == .success
        }
        #expect(recovered)
        #expect(await transport.fileImagesCallCount() == 2)
    }

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
        let runner = try #require(harness.recordedRunner)
        #expect(await runner.recordedCalls() == ["FILE1|1:2", "FILE2|3:4"])
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
            callStrategy: .singleForBatch,
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
        #expect(restoredHarness.viewModel.callStrategy == .singleForBatch)
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
            callStrategy: .singlePerLink,
            items: [item]
        ))

        harness.viewModel.loadBatchIntoWorkspace(persisted)

        #expect(harness.viewModel.currentBatchID == "batch-1")
        #expect(harness.viewModel.currentBatchDirectory == persisted.batchDirectory.path)
        #expect(harness.viewModel.promptTemplate == "batch prompt")
        #expect(harness.viewModel.inputText == "batch input")
        #expect(harness.viewModel.mode == .parallel)
        #expect(harness.viewModel.parallelism == 5)
        #expect(harness.viewModel.callStrategy == .singlePerLink)
        #expect(harness.viewModel.items == [item])

        let draft = try #require(harness.draftStore.load())
        #expect(draft.currentBatchID == "batch-1")
        #expect(draft.parallelism == 5)
        #expect(draft.callStrategy == .singlePerLink)
    }

    @Test func selectingAgentImmediatelyPersistsToSettingsStore() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.selectedAgentID = AgentProvider.claude.id

        let settings = try harness.settingsStore.load()
        #expect(settings.selectedAgentID == AgentProvider.claude.id)
    }

    @Test func clearingAgentSelectionPersistsNilToSettingsStore() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)

        harness.viewModel.selectedAgentID = nil

        let settings = try harness.settingsStore.load()
        #expect(settings.selectedAgentID == nil)
    }

    @Test func bootstrapDoesNotOverridePersistedSelectedAgentWithDraftSelection() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        let draft = GenerateWorkspaceDraft(
            selectedAgentID: AgentProvider.claude.id,
            promptTemplate: "draft prompt",
            outputDirectoryPath: sandbox.root.path,
            mode: .sequential,
            parallelism: 2,
            callStrategy: .singlePerLink,
            inputText: "draft",
            items: [],
            selectedItemID: nil,
            currentBatchID: nil,
            currentBatchDirectory: nil
        )
        try harness.draftStore.save(draft)

        let restoredHarness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        await restoredHarness.viewModel.bootstrap()

        let settings = try restoredHarness.settingsStore.load()
        #expect(restoredHarness.viewModel.selectedAgentID == AgentProvider.claude.id)
        #expect(settings.selectedAgentID == AgentProvider.codex.id)
    }

    @Test func generateCapturesRealtimeConsoleLogForSelectedItem() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: StreamingRecordingAgentRunner(mode: .single))
        let item = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        harness.viewModel.items = [item]
        harness.viewModel.selectedItemID = item.id

        await harness.viewModel.generate()

        let log = try #require(harness.viewModel.selectedRunLog)
        #expect(log.isShared == false)
        #expect(log.combinedConsoleText.contains("stdout-line"))
        #expect(log.combinedConsoleText.contains("stderr-line"))
        #expect(log.exitCode == 0)
    }

    @Test func singleBatchStrategySharesRealtimeConsoleLogAcrossItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root, runner: StreamingRecordingAgentRunner(mode: .batch))
        harness.viewModel.callStrategy = .singleForBatch
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")
        harness.viewModel.items = [first, second]

        harness.viewModel.selectedItemID = first.id
        await harness.viewModel.generate()
        let firstLog = try #require(harness.viewModel.selectedRunLog)

        harness.viewModel.selectedItemID = second.id
        let secondLog = try #require(harness.viewModel.selectedRunLog)

        #expect(firstLog.runID == secondLog.runID)
        #expect(firstLog.isShared)
        #expect(secondLog.isShared)
        #expect(secondLog.combinedConsoleText.contains("shared-batch-line"))
    }
}

@MainActor
private struct GenerateViewModelHarness {
    let viewModel: GenerateViewModel
    let runner: any AgentRunning
    let recordedRunner: RecordingAgentRunner?
    let batchStore: BatchStore
    let draftStore: GenerateWorkspaceDraftStore
    let settingsStore: SettingsStore

    init(
        rootDirectory: URL,
        figmaTransport: (any FigmaHTTPTransport)? = nil,
        figmaToken: String = "",
        runner: (any AgentRunning)? = nil
    ) throws {
        let settingsStore = SettingsStore(fileURL: rootDirectory.appendingPathComponent("settings.json"))
        try settingsStore.save(AppSettings(
            selectedAgentID: AgentProvider.codex.id,
            promptTemplate: "prompt",
            outputDirectoryPath: rootDirectory.path,
            figmaToken: figmaToken,
            defaultExportFormat: .png,
            defaultGenerationMode: .sequential,
            parallelism: 2,
            defaultAgentCallStrategy: .singlePerLink
        ))
        let agentService = AgentService(shellClient: ShellClient(environment: [:]))
        let figmaService: FigmaService
        if let figmaTransport {
            figmaService = FigmaService(baseDirectory: rootDirectory, transport: figmaTransport)
        } else {
            figmaService = FigmaService(baseDirectory: rootDirectory)
        }
        let settingsViewModel = SettingsViewModel(settingsStore: settingsStore, agentService: agentService, figmaService: figmaService)
        settingsViewModel.settings = try settingsStore.load()
        let batchStore = BatchStore(rootDirectory: rootDirectory)
        let draftStore = GenerateWorkspaceDraftStore(fileURL: rootDirectory.appendingPathComponent("generate-workspace-draft.json"))
        let resolvedRunner = runner ?? RecordingAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: resolvedRunner)
        let viewModel = GenerateViewModel(
            settingsViewModel: settingsViewModel,
            batchStore: batchStore,
            generationCoordinator: coordinator,
            figmaService: figmaService,
            draftStore: draftStore
        )

        self.viewModel = viewModel
        self.runner = resolvedRunner
        self.recordedRunner = resolvedRunner as? RecordingAgentRunner
        self.batchStore = batchStore
        self.draftStore = draftStore
        self.settingsStore = settingsStore

        viewModel.availableAgents = [AgentDescriptor(provider: .codex, path: "/mock/codex", version: "1.0")]
        viewModel.selectedAgentID = AgentProvider.codex.id
        viewModel.promptTemplate = "prompt"
        viewModel.outputDirectoryPath = rootDirectory.path
        viewModel.mode = GenerationMode.sequential
        viewModel.parallelism = 2
        viewModel.callStrategy = .singlePerLink
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    intervalNanoseconds: UInt64 = 20_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await MainActor.run(body: condition) {
            return true
        }
        try? await Task.sleep(nanoseconds: intervalNanoseconds)
    }
    return await MainActor.run(body: condition)
}

private actor FlakyFileImagesTransport: FigmaHTTPTransport {
    private var fileImagesCalls = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
        let path = url.path

        switch path {
        case "/v1/files/FILE1/nodes":
            return response(
                url: url,
                status: 200,
                body: """
                {
                  "nodes": {
                    "1:2": {
                      "document": {
                        "id": "1:2",
                        "name": "Node 1",
                        "fills": [{ "type": "IMAGE", "imageRef": "img-ref-1" }],
                        "children": []
                      }
                    }
                  }
                }
                """
            )
        case "/v1/images/FILE1":
            if query["ids"] == "1:2" {
                return response(url: url, status: 200, body: #"{"images":{"1:2":"https://cdn.figma.test/preview.png"}}"#)
            }
        case "/v1/files/FILE1/images":
            fileImagesCalls += 1
            if fileImagesCalls == 1 {
                return response(url: url, status: 500, body: #"{"err":"temporary"}"#)
            }
            return response(url: url, status: 200, body: #"{"meta":{"images":{"img-ref-1":"https://cdn.figma.test/resource.png"}}}"#)
        default:
            break
        }

        if url.absoluteString == "https://cdn.figma.test/preview.png" {
            return response(url: url, status: 200, data: Data("PNG".utf8))
        }
        if url.absoluteString == "https://cdn.figma.test/resource.png" {
            return response(url: url, status: 200, data: Data("RES".utf8))
        }
        throw URLError(.badServerResponse)
    }

    func fileImagesCallCount() -> Int {
        fileImagesCalls
    }

    private func response(url: URL, status: Int, body: String) -> (Data, HTTPURLResponse) {
        let data = Data(body.utf8)
        let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }

    private func response(url: URL, status: Int, data: Data) -> (Data, HTTPURLResponse) {
        let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, http)
    }
}

private actor RecordingAgentRunner: AgentRunning {
    private var calls: [String] = []

    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil
    ) async throws -> AgentRunResult {
        calls.append("\(item.fileKey)|\(item.nodeId)")
        if prompt.contains("待处理链接：") {
            return AgentRunResult(
                output: """
                <<<FIGBRIDGE_YAML_START fileKey=FILE1 nodeId=1:2>>>
                name: 1:2
                <<<FIGBRIDGE_YAML_END>>>
                <<<FIGBRIDGE_YAML_START fileKey=FILE2 nodeId=3:4>>>
                name: 3:4
                <<<FIGBRIDGE_YAML_END>>>
                """,
                executablePath: "/mock/\(provider.rawValue)",
                arguments: [],
                exitCode: 0,
                stderr: ""
            )
        }
        return AgentRunResult(output: "name: \(item.nodeId)", executablePath: "/mock/\(provider.rawValue)", arguments: [], exitCode: 0, stderr: "")
    }

    func recordedCalls() -> [String] {
        calls
    }
}

private actor StreamingRecordingAgentRunner: AgentRunning {
    enum Mode {
        case single
        case batch
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func run(
        provider: AgentProvider,
        prompt: String,
        item: FigmaLinkItem,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)?
    ) async throws -> AgentRunResult {
        switch mode {
        case .single:
            if let eventHandler {
                await eventHandler(.started(executablePath: "/mock/\(provider.rawValue)", arguments: [], isSharedLog: false))
                await eventHandler(.stdout("stdout-line\n"))
                await eventHandler(.stderr("stderr-line\n"))
                await eventHandler(.finished(exitCode: 0))
            }
            return AgentRunResult(output: "name: \(item.nodeId)", executablePath: "/mock/\(provider.rawValue)", arguments: [], exitCode: 0, stderr: "stderr-line")
        case .batch:
            if let eventHandler {
                await eventHandler(.started(executablePath: "/mock/\(provider.rawValue)", arguments: [], isSharedLog: true))
                await eventHandler(.stdout("shared-batch-line\n"))
                await eventHandler(.finished(exitCode: 0))
            }
            return AgentRunResult(
                output: """
                <<<FIGBRIDGE_YAML_START fileKey=FILE1 nodeId=1:2>>>
                name: 1:2
                <<<FIGBRIDGE_YAML_END>>>
                <<<FIGBRIDGE_YAML_START fileKey=FILE2 nodeId=3:4>>>
                name: 3:4
                <<<FIGBRIDGE_YAML_END>>>
                """,
                executablePath: "/mock/\(provider.rawValue)",
                arguments: [],
                exitCode: 0,
                stderr: ""
            )
        }
    }
}

extension GenerateViewModelTests {
    @Test func singleBatchStrategyCallsRunnerOnlyOnceForMultipleItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let harness = try GenerateViewModelHarness(rootDirectory: sandbox.root)
        harness.viewModel.callStrategy = .singleForBatch
        let first = FigmaLinkItem(rawInputLine: "one", title: "One", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let second = FigmaLinkItem(rawInputLine: "two", title: "Two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")
        harness.viewModel.items = [first, second]

        await harness.viewModel.generate()

        let runner = try #require(harness.recordedRunner)
        #expect(await runner.recordedCalls() == ["FILE1|1:2"])
        #expect(harness.viewModel.items.allSatisfy { $0.generatedYAMLPath != nil })
    }
}
