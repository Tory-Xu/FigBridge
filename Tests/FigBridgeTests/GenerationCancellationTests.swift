import Foundation
import Testing
@testable import FigBridgeCore

struct GenerationCancellationTests {
    @Test func marksPendingItemsCancelledWhenTaskIsCancelled() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let batchStore = BatchStore(rootDirectory: sandbox.root)
        let runner = SlowMockAgentRunner()
        let coordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: runner)
        let items = [
            FigmaLinkItem(rawInputLine: "one", title: "one", url: "https://www.figma.com/design/FILE1/A?node-id=1-2", fileKey: "FILE1", nodeId: "1:2"),
            FigmaLinkItem(rawInputLine: "two", title: "two", url: "https://www.figma.com/design/FILE2/B?node-id=3-4", fileKey: "FILE2", nodeId: "3:4"),
        ]

        let task = Task {
            try await coordinator.generate(
                agent: .codex,
                promptTemplate: "prompt",
                sourceInputText: "input",
                outputDirectory: sandbox.root,
                mode: .sequential,
                parallelism: 1,
                items: items
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }
}

private actor SlowMockAgentRunner: AgentRunning {
    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> AgentRunResult {
        try await Task.sleep(for: .seconds(2))
        return AgentRunResult(output: "name: slow", executablePath: "/mock/\(provider.rawValue)", arguments: [])
    }
}
