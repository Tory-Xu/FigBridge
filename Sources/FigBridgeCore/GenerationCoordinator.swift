import Foundation

public protocol AgentRunning: Sendable {
    func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> AgentRunResult
}

extension AgentService: AgentRunning {
    public func run(provider: AgentProvider, prompt: String, item: FigmaLinkItem) async throws -> AgentRunResult {
        try await runDetailed(provider: provider, prompt: prompt)
    }
}

public struct GenerationCoordinator: Sendable {
    public let batchStore: BatchStore
    public let agentRunner: AgentRunning

    public init(batchStore: BatchStore, agentRunner: AgentRunning) {
        self.batchStore = batchStore
        self.agentRunner = agentRunner
    }

    public func generate(
        agent: AgentProvider,
        promptTemplate: String,
        sourceInputText: String,
        outputDirectory: URL,
        mode: GenerationMode,
        parallelism: Int,
        existingBatchID: String? = nil,
        items: [FigmaLinkItem],
        itemStarted: (@Sendable (FigmaLinkItem) async -> Void)? = nil,
        progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)? = nil
    ) async throws -> PersistedBatch {
        let existingBatch = try existingBatchID.flatMap { try batchStore.loadBatch(id: $0) }
        let batchID = existingBatch?.summary.id ?? BatchNaming.makeBatchID()
        let batchDirectory = outputDirectory.appendingPathComponent(batchID, isDirectory: true)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)

        let pendingItems = items.filter { $0.generatedYAMLPath == nil }
        let resolvedPendingItems: [FigmaLinkItem]

        switch mode {
        case .sequential:
            resolvedPendingItems = try await runSequential(items: pendingItems, provider: agent, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted, progress: progress)
        case .parallel:
            resolvedPendingItems = try await runParallel(items: pendingItems, provider: agent, promptTemplate: promptTemplate, batchDirectory: batchDirectory, parallelism: parallelism, itemStarted: itemStarted, progress: progress)
        }

        let resolvedMap = Dictionary(uniqueKeysWithValues: resolvedPendingItems.map { ($0.id, $0) })
        let resolvedItems = items.map { resolvedMap[$0.id] ?? $0 }

        if existingBatch == nil {
            let batch = GenerationBatch(
                id: batchID,
                createdAt: Date(),
                agent: agent,
                promptSnapshot: promptTemplate,
                sourceInputText: sourceInputText,
                outputDirectory: outputDirectory.path,
                mode: mode,
                items: resolvedItems
            )
            return try batchStore.createBatch(batch)
        }

        return try batchStore.updateBatch(
            id: batchID,
            sourceInputText: sourceInputText,
            agent: agent,
            promptSnapshot: promptTemplate,
            outputDirectory: outputDirectory,
            mode: mode,
            items: resolvedItems
        )
    }

    private func runSequential(items: [FigmaLinkItem], provider: AgentProvider, promptTemplate: String, batchDirectory: URL, itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?, progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)?) async throws -> [FigmaLinkItem] {
        var resolved: [FigmaLinkItem] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let result = try await runSingle(item: item, index: index, provider: provider, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted)
            resolved.append(result)
            if let progress {
                await progress(index + 1, items.count, result)
            }
        }
        return resolved
    }

    private func runParallel(items: [FigmaLinkItem], provider: AgentProvider, promptTemplate: String, batchDirectory: URL, parallelism: Int, itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?, progress: (@Sendable (Int, Int, FigmaLinkItem) async -> Void)?) async throws -> [FigmaLinkItem] {
        let limit = max(1, parallelism)
        var iterator = items.enumerated().makeIterator()
        var results = Array<FigmaLinkItem?>(repeating: nil, count: items.count)
        var completedCount = 0

        try await withThrowingTaskGroup(of: (Int, FigmaLinkItem).self) { group in
            for _ in 0..<min(limit, items.count) {
                guard let next = iterator.next() else {
                    break
                }
                group.addTask {
                    let resolved = try await runSingle(item: next.element, index: next.offset, provider: provider, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted)
                    return (next.offset, resolved)
                }
            }

            while let completed = try await group.next() {
                try Task.checkCancellation()
                results[completed.0] = completed.1
                completedCount += 1
                if let progress {
                    await progress(completedCount, items.count, completed.1)
                }
                if let next = iterator.next() {
                    group.addTask {
                        let resolved = try await runSingle(item: next.element, index: next.offset, provider: provider, promptTemplate: promptTemplate, batchDirectory: batchDirectory, itemStarted: itemStarted)
                        return (next.offset, resolved)
                    }
                }
            }
        }

        return results.compactMap { $0 }
    }

    private func runSingle(item: FigmaLinkItem, index: Int, provider: AgentProvider, promptTemplate: String, batchDirectory: URL, itemStarted: (@Sendable (FigmaLinkItem) async -> Void)?) async throws -> FigmaLinkItem {
        var resolvedItem = item
        resolvedItem.generationStatus = .running
        resolvedItem.logSummary = "执行中"
        if let itemStarted {
            await itemStarted(resolvedItem)
        }
        try Task.checkCancellation()
        let prompt = PromptBuilder.makePrompt(template: promptTemplate, item: item)
        let itemDirectory = batchDirectory.appendingPathComponent("items/\(item.id.uuidString.lowercased())-\(item.nodeId.replacingOccurrences(of: ":", with: "-"))", isDirectory: true)
        let yamlDirectory = itemDirectory.appendingPathComponent("yaml", isDirectory: true)
        try FileManager.default.createDirectory(at: yamlDirectory, withIntermediateDirectories: true)

        do {
            let result = try await agentRunner.run(provider: provider, prompt: prompt, item: item)
            let yamlURL = yamlDirectory.appendingPathComponent("figma-node-\(item.nodeId.replacingOccurrences(of: ":", with: "-")).yaml")
            let rawOutputURL = yamlDirectory.appendingPathComponent("agent-output.txt")
            try result.output.write(to: rawOutputURL, atomically: true, encoding: .utf8)
            try result.output.write(to: yamlURL, atomically: true, encoding: .utf8)
            resolvedItem.generatedYAMLPath = yamlURL.path
            resolvedItem.agentOutputPath = rawOutputURL.path
            resolvedItem.generationStatus = .success
            resolvedItem.errorMessage = nil
            resolvedItem.logSummary = "\(provider.displayName) 已执行：\(result.executablePath)"
        } catch {
            resolvedItem.generationStatus = .failed
            resolvedItem.generatedYAMLPath = nil
            resolvedItem.agentOutputPath = nil
            resolvedItem.errorMessage = error.localizedDescription
            resolvedItem.logSummary = "执行失败"
        }

        return resolvedItem
    }
}

enum BatchNaming {
    static func makeBatchID(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-'batch'"
        return formatter.string(from: date)
    }
}

enum PromptBuilder {
    static func makePrompt(template: String, item: FigmaLinkItem) -> String {
        """
        \(template)

        Figma URL: \(item.url)
        File Key: \(item.fileKey)
        Node ID: \(item.nodeId)
        Title: \(item.title ?? "")
        """
    }
}
