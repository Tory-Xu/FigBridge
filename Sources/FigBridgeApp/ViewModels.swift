import AppKit
import Foundation
import SwiftUI
import FigBridgeCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = .defaultValue
    @Published var availableAgents: [AgentDescriptor] = []
    @Published var message: String = ""
    @Published var isError: Bool = false

    private let settingsStore: SettingsStore
    private let agentService: AgentService
    private let figmaService: FigmaService
    private var bootstrapped = false

    init(settingsStore: SettingsStore, agentService: AgentService, figmaService: FigmaService) {
        self.settingsStore = settingsStore
        self.agentService = agentService
        self.figmaService = figmaService
    }

    func bootstrap() async {
        guard !bootstrapped else {
            return
        }
        bootstrapped = true
        do {
            availableAgents = try await agentService.detectAvailableAgents()
            settings = try settingsStore.loadValidatingSelectedAgent(availableAgents: availableAgents.map(\.provider))
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func refreshAgents() async {
        do {
            availableAgents = try await agentService.detectAvailableAgents()
            settings = try settingsStore.loadValidatingSelectedAgent(availableAgents: availableAgents.map(\.provider))
            message = "Agent 列表已刷新"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func testToken() async {
        do {
            try await figmaService.validateToken(settings.figmaToken)
            message = "Token 可用"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func restoreDefaultPrompt() {
        settings.promptTemplate = AppSettings.defaultPrompt
    }

    func save() {
        do {
            try settingsStore.save(settings)
            message = "设置已保存"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    func chooseDefaultOutputDirectory() {
        if let selectedURL = DesktopSupport.chooseDirectory(canCreateDirectories: true) {
            settings.outputDirectoryPath = selectedURL.path
        }
    }
}

@MainActor
final class GenerateViewModel: ObservableObject {
    @Published var availableAgents: [AgentDescriptor] = []
    @Published var selectedAgentID: String?
    @Published var promptTemplate: String = AppSettings.defaultPrompt
    @Published var outputDirectoryPath: String = ""
    @Published var mode: GenerationMode = .sequential
    @Published var parallelism: Int = 2
    @Published var inputText: String = ""
    @Published var items: [FigmaLinkItem] = []
    @Published var selectedItemID: UUID?
    @Published var validationMessage: String = ""
    @Published var exportMessage: String = ""
    @Published var isGenerating: Bool = false
    @Published var progressText: String = ""
    @Published var completedCount: Int = 0
    @Published var currentBatchID: String?
    @Published var currentBatchDirectory: String?

    private let settingsViewModel: SettingsViewModel
    private let batchStore: BatchStore
    private let generationCoordinator: GenerationCoordinator
    private let figmaService: FigmaService
    private let parser = FigmaLinkParser()
    private var bootstrapped = false
    private var generationTask: Task<PersistedBatch, Error>?

    init(settingsViewModel: SettingsViewModel, batchStore: BatchStore, generationCoordinator: GenerationCoordinator, figmaService: FigmaService) {
        self.settingsViewModel = settingsViewModel
        self.batchStore = batchStore
        self.generationCoordinator = generationCoordinator
        self.figmaService = figmaService
    }

    var selectedItem: FigmaLinkItem? {
        guard let selectedItemID else {
            return nil
        }
        return items.first(where: { $0.id == selectedItemID })
    }

    var pendingItems: [FigmaLinkItem] {
        items.filter { $0.generatedYAMLPath == nil }
    }

    var processedItems: [FigmaLinkItem] {
        items.filter { $0.generatedYAMLPath != nil }
    }

    var canGenerate: Bool {
        !isGenerating
        && selectedAgentID != nil
        && !promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !outputDirectoryPath.isEmpty
        && !pendingItems.isEmpty
    }

    func bootstrap() async {
        guard !bootstrapped else {
            return
        }
        bootstrapped = true
        await settingsViewModel.bootstrap()
        availableAgents = settingsViewModel.availableAgents
        selectedAgentID = settingsViewModel.settings.selectedAgentID
        promptTemplate = settingsViewModel.settings.promptTemplate
        outputDirectoryPath = settingsViewModel.settings.outputDirectoryPath ?? batchStore.rootDirectory.path
        mode = settingsViewModel.settings.defaultGenerationMode
        parallelism = settingsViewModel.settings.parallelism
    }

    func addInput() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            validationMessage = "请输入要添加的信息"
            return
        }

        let result = parser.parse(inputText)
        validationMessage = result.errors.joined(separator: "\n")
        let existing = Set(items.map { "\($0.fileKey)|\($0.nodeId)" })
        let newItems = result.items.filter { !existing.contains("\($0.fileKey)|\($0.nodeId)") }
        items.append(contentsOf: newItems)
        if !newItems.isEmpty {
            inputText = ""
        }
        if selectedItemID == nil {
            selectedItemID = items.first?.id
        }
    }

    func resetWorkspace() {
        inputText = ""
        items = []
        selectedItemID = nil
        validationMessage = ""
        exportMessage = ""
        progressText = ""
        completedCount = 0
        currentBatchID = nil
        currentBatchDirectory = nil
    }

    func generate() async {
        guard canGenerate else {
            validationMessage = "请先完成 agent、prompt、输出目录和链接校验"
            return
        }
        guard let selectedAgentID,
              let provider = AgentProvider.allCases.first(where: { $0.id == selectedAgentID }) else {
            validationMessage = "未选择 agent"
            return
        }

        isGenerating = true
        completedCount = 0
        let pendingItemIDs = Set(pendingItems.map(\.id))
        let pendingTotal = pendingItemIDs.count
        progressText = "准备生成 \(pendingTotal) 项"
        validationMessage = ""
        for index in items.indices {
            guard pendingItemIDs.contains(items[index].id) else {
                continue
            }
            items[index].generationStatus = .queued
            items[index].logSummary = "等待执行"
            items[index].errorMessage = nil
        }

        let task = Task<PersistedBatch, Error> {
            try await generationCoordinator.generate(
                agent: provider,
                promptTemplate: promptTemplate,
                sourceInputText: inputText,
                outputDirectory: URL(fileURLWithPath: outputDirectoryPath, isDirectory: true),
                mode: mode,
                parallelism: parallelism,
                existingBatchID: currentBatchID,
                items: items,
                progress: { [weak self] completed, total, item in
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.completedCount = completed
                        self.progressText = "已完成 \(completed)/\(total)：\(item.title ?? item.nodeName ?? item.nodeId)"
                        if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[index] = item
                        }
                    }
                }
            )
        }
        generationTask = task

        do {
            let persisted = try await task.value
            items = persisted.summary.items
            currentBatchID = persisted.summary.id
            currentBatchDirectory = persisted.batchDirectory.path
            validationMessage = "生成完成"
        } catch is CancellationError {
            validationMessage = "生成已取消"
        } catch {
            validationMessage = error.localizedDescription
        }

        isGenerating = false
        generationTask = nil
    }

    func cancelGeneration() {
        generationTask?.cancel()
    }

    func deleteItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        let removedItem = items.remove(at: index)

        if let currentBatchID {
            do {
                try batchStore.deleteBatchItem(batchID: currentBatchID, itemID: removedItem.id)
            } catch {
                validationMessage = error.localizedDescription
            }
        }

        if selectedItemID == removedItem.id {
            let nextSelection = items.indices.contains(index) ? items[index].id : items.last?.id
            selectedItemID = nextSelection
        }
    }

    func chooseOutputDirectory() {
        if let selectedURL = DesktopSupport.chooseDirectory(canCreateDirectories: true) {
            outputDirectoryPath = selectedURL.path
        }
    }

    func loadSelectedItemPreviewIfNeeded() async {
        guard let selectedItemID,
              let index = items.firstIndex(where: { $0.id == selectedItemID }) else {
            return
        }
        let token = settingsViewModel.settings.figmaToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }
        if items[index].previewStatus == .success || items[index].resourceStatus == .success {
            return
        }

        items[index].previewStatus = .loading
        items[index].resourceStatus = .loading
        do {
            let resolved = try await figmaService.loadPreviewAndResources(for: items[index], token: token)
            items[index] = resolved
        } catch {
            items[index].previewStatus = .failed
            items[index].resourceStatus = .failed
            items[index].errorMessage = error.localizedDescription
        }
    }

    func exportPreviewImage() {
        guard let item = selectedItem,
              let previewPath = item.previewImagePath else {
            return
        }
        exportLocalFile(at: URL(fileURLWithPath: previewPath), preferredName: "\(item.nodeId.replacingOccurrences(of: ":", with: "-"))-preview.png")
    }

    func exportResource(_ resource: FigmaResourceItem) {
        guard let localPath = resource.localPath else {
            return
        }
        exportLocalFile(at: URL(fileURLWithPath: localPath), preferredName: "\(resource.name).\(resource.format.rawValue)")
    }

    func exportAllResources() {
        guard let item = selectedItem,
              let destinationDirectory = DesktopSupport.chooseDirectory(canCreateDirectories: true) else {
            return
        }
        do {
            for resource in item.resourceItems {
                guard let localPath = resource.localPath else {
                    continue
                }
                let sourceURL = URL(fileURLWithPath: localPath)
                _ = try batchStore.copyFileToDirectory(sourceURL, destinationDirectory: destinationDirectory, preferredName: "\(resource.name).\(resource.format.rawValue)")
            }
            exportMessage = "资源已导出到 \(destinationDirectory.path)"
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private func exportLocalFile(at sourceURL: URL, preferredName: String) {
        guard let destinationDirectory = DesktopSupport.chooseDirectory(canCreateDirectories: true) else {
            return
        }
        do {
            let copiedURL = try batchStore.copyFileToDirectory(sourceURL, destinationDirectory: destinationDirectory, preferredName: preferredName)
            exportMessage = "已导出 \(copiedURL.lastPathComponent)"
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var batches: [PersistedBatch] = []
    @Published var selectedBatchID: String? {
        didSet {
            guard !isSynchronizingSelection, oldValue != selectedBatchID else {
                return
            }
            synchronizeSelectionForCurrentBatch(resetItemSelection: true)
        }
    }
    @Published var selectedItemID: UUID? {
        didSet {
            guard !isSynchronizingSelection, oldValue != selectedItemID else {
                return
            }
            synchronizeSelectedItem()
        }
    }
    @Published var selectedYAMLText: String?
    @Published var selectedSourceInputText: String?
    @Published var message: String = ""

    private let batchStore: BatchStore
    private var isSynchronizingSelection = false

    init(batchStore: BatchStore) {
        self.batchStore = batchStore
    }

    var selectedBatch: PersistedBatch? {
        guard let selectedBatchID else {
            return nil
        }
        return batches.first(where: { $0.summary.id == selectedBatchID })
    }

    var selectedItem: FigmaLinkItem? {
        guard let selectedItemID else {
            return nil
        }
        return selectedBatch?.summary.items.first(where: { $0.id == selectedItemID })
    }

    var canCopyPrompt: Bool {
        guard let batch = selectedBatch else {
            return false
        }
        return batch.summary.items.contains { $0.generatedYAMLPath != nil }
    }

    func reload() {
        do {
            batches = try batchStore.scanBatches()
            synchronizeSelectionForCurrentBatch(resetItemSelection: false)
            message = ""
        } catch {
            batches = []
            message = error.localizedDescription
        }
    }

    func copyPrompt() {
        guard let batch = selectedBatch else {
            return
        }
        let prompt = batchStore.makeCopyPrompt(for: batch.summary.items.filter { $0.generatedYAMLPath != nil })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        message = "Prompt 已复制"
    }

    func exportSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        let baseDirectory = DesktopSupport.chooseDirectory(canCreateDirectories: true) ?? batch.batchDirectory.deletingLastPathComponent()
        let destinationURL = baseDirectory.appendingPathComponent("\(batch.summary.id).zip")
        do {
            try batchStore.exportBatch(at: batch.batchDirectory, to: destinationURL)
            message = "已导出到 \(destinationURL.path)"
        } catch {
            message = error.localizedDescription
        }
    }

    func importBatchZipUsingPanel() {
        guard let zipURL = DesktopSupport.chooseZipArchive() else {
            return
        }
        do {
            _ = try batchStore.importBatchArchive(from: zipURL)
            reload()
            message = "已导入 \(zipURL.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    func importBatchDirectoryUsingPanel() {
        guard let directoryURL = DesktopSupport.chooseDirectory() else {
            return
        }
        do {
            _ = try batchStore.importBatchDirectory(from: directoryURL)
            reload()
            message = "已导入 \(directoryURL.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    func openSelectedBatchInFinder() {
        guard let batch = selectedBatch else {
            return
        }
        DesktopSupport.openInFinder(batch.batchDirectory)
    }

    func deleteSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        do {
            try batchStore.deleteBatch(at: batch.batchDirectory)
            selectedBatchID = nil
            selectedItemID = nil
            reload()
            message = "已删除 \(batch.summary.id)"
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadSelectedYAML() {
        guard let yamlPath = selectedItem?.generatedYAMLPath else {
            selectedYAMLText = nil
            return
        }
        selectedYAMLText = try? String(contentsOfFile: yamlPath, encoding: .utf8)
    }

    private func loadSelectedSourceInput() {
        guard let batch = selectedBatch else {
            selectedSourceInputText = nil
            return
        }
        let sourceInputURL = batch.batchDirectory.appendingPathComponent("source-input.txt")
        selectedSourceInputText = try? String(contentsOf: sourceInputURL, encoding: .utf8)
    }

    private func synchronizeSelectionForCurrentBatch(resetItemSelection: Bool) {
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }

        let availableBatchIDs = Set(batches.map(\.summary.id))
        if let selectedBatchID, !availableBatchIDs.contains(selectedBatchID) {
            self.selectedBatchID = nil
        }
        if self.selectedBatchID == nil {
            self.selectedBatchID = batches.first?.summary.id
        }

        loadSelectedSourceInput()

        guard let batch = selectedBatch else {
            selectedItemID = nil
            selectedYAMLText = nil
            return
        }

        let availableItemIDs = Set(batch.summary.items.map(\.id))
        if resetItemSelection || selectedItemID == nil || !availableItemIDs.contains(selectedItemID!) {
            selectedItemID = batch.summary.items.first?.id
        }

        loadSelectedYAML()
    }

    private func synchronizeSelectedItem() {
        guard let batch = selectedBatch else {
            selectedYAMLText = nil
            return
        }

        if let currentSelectedItemID = selectedItemID, !batch.summary.items.contains(where: { $0.id == currentSelectedItemID }) {
            isSynchronizingSelection = true
            self.selectedItemID = batch.summary.items.first?.id
            isSynchronizingSelection = false
        }

        loadSelectedYAML()
    }
}
