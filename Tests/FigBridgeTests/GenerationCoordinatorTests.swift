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
}

private actor MockAgentRunner: AgentRunning {
    let outputs: [String: Result<String, Error>]

    init(outputs: [String: Result<String, Error>]) {
        self.outputs = outputs
    }

    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> String {
        let key = "\(item.fileKey)|\(item.nodeId)"
        guard let result = outputs[key] else {
            throw MockFailure()
        }
        return try result.get()
    }
}

private struct MockFailure: LocalizedError {
    var errorDescription: String? { "mock failure" }
}
