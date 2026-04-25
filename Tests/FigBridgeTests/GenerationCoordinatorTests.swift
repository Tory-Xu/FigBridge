import Foundation
import Testing
@testable import FigBridgeCore

struct GenerationCoordinatorTests {
    @Test func runsSequentialGenerationAndPersistsOutputs() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success("name: first"),
            "FILE2|3:4": .success("name: second"),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)

        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let batch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            items: items
        )

        #expect(batch.summary.items.allSatisfy { $0.generationStatus == .success })
        #expect(batch.summary.items.allSatisfy { $0.generatedYAMLPath != nil })
    }

    @Test func runsParallelGenerationAndKeepsFailures() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success("name: first"),
            "FILE2|3:4": .failure(MockFailure()),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)

        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let batch = try await coordinator.generate(
            agent: .claude,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .parallel,
            parallelism: 2,
            items: items
        )

        #expect(batch.summary.items.filter { $0.generationStatus == .success }.count == 1)
        #expect(batch.summary.items.filter { $0.generationStatus == .failed }.count == 1)
    }

    @Test func reusesExistingBatchAndOnlyRunsPendingItems() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = MockAgentRunner(outputs: [
            "FILE1|1:2": .success("name: first"),
            "FILE2|3:4": .success("name: second"),
        ])
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)

        let firstItem = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")
        let secondItem = FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4")

        let firstBatch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            items: [firstItem]
        )

        let secondBatch = try await coordinator.generate(
            agent: .codex,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 2,
            existingBatchID: firstBatch.summary.id,
            items: firstBatch.summary.items + [secondItem]
        )

        let calls = await runner.recordedCalls()
        #expect(firstBatch.summary.id == secondBatch.summary.id)
        #expect(secondBatch.summary.items.count == 2)
        #expect(calls == ["FILE1|1:2", "FILE2|3:4"])
    }

    @Test func retriesFailedItemsOnLaterGeneration() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = RetryingMockAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let item = FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2")

        let firstBatch = try await coordinator.generate(
            agent: .claude,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            items: [item]
        )

        #expect(firstBatch.summary.items[0].generationStatus == .failed)

        let retriedBatch = try await coordinator.generate(
            agent: .claude,
            promptTemplate: "prompt",
            sourceInputText: "input",
            outputDirectory: sandbox.root,
            mode: .sequential,
            parallelism: 1,
            existingBatchID: firstBatch.summary.id,
            items: firstBatch.summary.items
        )

        #expect(retriedBatch.summary.items[0].generationStatus == .success)
        #expect(retriedBatch.summary.items[0].generatedYAMLPath != nil)
        #expect(await runner.recordedCalls() == ["FILE1|1:2", "FILE1|1:2"])
    }
}

private actor MockAgentRunner: AgentRunning {
    let outputs: [String: Result<String, Error>]
    private var calls: [String] = []

    init(outputs: [String: Result<String, Error>]) {
        self.outputs = outputs
    }

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> AgentRunResult {
        let key = "\(item.fileKey)|\(item.nodeId)"
        calls.append(key)
        guard let result = outputs[key] else {
            throw MockFailure()
        }
        return AgentRunResult(output: try result.get(), executablePath: "/mock/\(provider.rawValue)", arguments: [])
    }

    func recordedCalls() -> [String] {
        calls
    }
}

private struct MockFailure: LocalizedError {
    var errorDescription: String? { "mock failure" }
}

private actor RetryingMockAgentRunner: AgentRunning {
    private var attempts: [String: Int] = [:]
    private var calls: [String] = []

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> AgentRunResult {
        let key = "\(item.fileKey)|\(item.nodeId)"
        calls.append(key)
        let nextAttempt = (attempts[key] ?? 0) + 1
        attempts[key] = nextAttempt
        if nextAttempt == 1 {
            throw MockFailure()
        }
        return AgentRunResult(output: "name: retried", executablePath: "/mock/\(provider.rawValue)", arguments: [])
    }

    func recordedCalls() -> [String] {
        calls
    }
}
