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

    func updateSelectedAgent(_ selectedAgentID: String?) {
        guard settings.selectedAgentID != selectedAgentID else {
            return
        }
        settings.selectedAgentID = selectedAgentID
        do {
            try settingsStore.save(settings)
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}

@MainActor
final class GenerateViewModel: ObservableObject {
    @Published var availableAgents: [AgentDescriptor] = []
    @Published var selectedAgentID: String? {
        didSet {
            guard oldValue != selectedAgentID else {
                return
            }
            persistDraftIfNeeded()
            persistSelectedAgentToSettingsIfNeeded()
        }
    }
    @Published var promptTemplate: String = AppSettings.defaultPrompt {
        didSet { persistDraftIfNeeded() }
    }
    @Published var outputDirectoryPath: String = "" {
        didSet { persistDraftIfNeeded() }
    }
    @Published var mode: GenerationMode = .sequential {
        didSet { persistDraftIfNeeded() }
    }
    @Published var parallelism: Int = 2 {
        didSet { persistDraftIfNeeded() }
    }
    @Published var inputText: String = "" {
        didSet { persistDraftIfNeeded() }
    }
    @Published var items: [FigmaLinkItem] = [] {
        didSet {
            if selectedItemID != nil {
                loadSelectedYAML()
            }
            persistDraftIfNeeded()
        }
    }
    @Published var selectedItemID: UUID? {
        didSet {
            guard oldValue != selectedItemID else {
                return
            }
            loadSelectedYAML()
            persistDraftIfNeeded()
        }
    }
    @Published var validationMessage: String = ""
    @Published var exportMessage: String = ""
    @Published var isGenerating: Bool = false
    @Published var progressText: String = ""
    @Published var completedCount: Int = 0
    @Published var currentBatchID: String? {
        didSet { persistDraftIfNeeded() }
    }
    @Published var currentBatchDirectory: String? {
        didSet { persistDraftIfNeeded() }
    }
    @Published var selectedYAMLText: String?
    @Published var renamingItemID: UUID?
    @Published var renamingTitle: String = ""
    @Published var renamingOriginalTitle: String = ""

    private let settingsViewModel: SettingsViewModel
    private let batchStore: BatchStore
    private let generationCoordinator: GenerationCoordinator
    private let figmaService: FigmaService
    private let draftStore: GenerateWorkspaceDraftStore
    private let parser = FigmaLinkParser()
    private var bootstrapped = false
    private var generationTask: Task<PersistedBatch, Error>?
    private var isRestoringWorkspace = false
    private var resourceLoadTasks: [UUID: Task<Void, Never>] = [:]

    init(settingsViewModel: SettingsViewModel, batchStore: BatchStore, generationCoordinator: GenerationCoordinator, figmaService: FigmaService, draftStore: GenerateWorkspaceDraftStore) {
        self.settingsViewModel = settingsViewModel
        self.batchStore = batchStore
        self.generationCoordinator = generationCoordinator
        self.figmaService = figmaService
        self.draftStore = draftStore
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
        isRestoringWorkspace = true
        applyDefaultWorkspaceSettings()
        if let draft = draftStore.load() {
            applyWorkspaceDraft(draft)
        }
        isRestoringWorkspace = false
        preloadResourcesForAllItemsIfNeeded()
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
        preloadResourcesForAllItemsIfNeeded()
    }

    func resetWorkspace() {
        startNewBatch()
    }

    func startNewBatch() {
        cancelGeneration()
        cancelAllResourceLoads()
        isRestoringWorkspace = true
        applyDefaultWorkspaceSettings()
        inputText = ""
        items = []
        selectedItemID = nil
        validationMessage = ""
        exportMessage = ""
        progressText = ""
        completedCount = 0
        currentBatchID = nil
        currentBatchDirectory = nil
        selectedYAMLText = nil
        isRestoringWorkspace = false
        persistDraft(force: true)
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
                itemStarted: { [weak self] item in
                    await MainActor.run {
                        guard let self,
                              let index = self.items.firstIndex(where: { $0.id == item.id }) else {
                            return
                        }
                        self.items[index] = item
                    }
                },
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
            loadSelectedYAML()
            validationMessage = "生成完成"
            persistDraftIfNeeded()
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
        cancelResourceLoad(for: id)
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
        loadSelectedYAML()
        persistDraftIfNeeded()
    }

    func chooseOutputDirectory() {
        if let selectedURL = DesktopSupport.chooseDirectory(canCreateDirectories: true) {
            outputDirectoryPath = selectedURL.path
        }
    }

    func loadSelectedItemPreviewIfNeeded() async {
        loadSelectedYAML()
        guard let selectedItemID else {
            return
        }
        scheduleResourceLoad(for: selectedItemID, force: false)
    }

    func preloadResourcesForAllItemsIfNeeded() {
        for item in items {
            scheduleResourceLoad(for: item.id, force: false)
        }
    }

    func reloadResources(for itemID: UUID) {
        scheduleResourceLoad(for: itemID, force: true)
    }

    func beginRenamingSelectedItem() {
        guard let item = selectedItem else {
            return
        }
        let originalTitle = item.title ?? item.nodeName ?? item.nodeId
        renamingItemID = item.id
        renamingTitle = originalTitle
        renamingOriginalTitle = originalTitle
    }

    func commitRename() {
        guard let renamingItemID,
              let index = items.firstIndex(where: { $0.id == renamingItemID }) else {
            cancelRename()
            return
        }

        let trimmedTitle = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].title = trimmedTitle.isEmpty ? nil : trimmedTitle

        if let currentBatchID {
            do {
                let persisted = try batchStore.updateBatchItem(batchID: currentBatchID, item: items[index])
                items = persisted.summary.items
                currentBatchDirectory = persisted.batchDirectory.path
            } catch {
                validationMessage = error.localizedDescription
            }
        }

        cancelRename()
        persistDraftIfNeeded()
    }

    func cancelRename() {
        renamingItemID = nil
        renamingTitle = ""
        renamingOriginalTitle = ""
    }

    func finishRenameOnBlur() {
        guard renamingItemID != nil else {
            return
        }
        let trimmedTitle = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == renamingOriginalTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
            cancelRename()
        } else {
            commitRename()
        }
    }

    private func loadSelectedYAML() {
        guard let yamlPath = selectedItem?.generatedYAMLPath else {
            selectedYAMLText = nil
            return
        }
        selectedYAMLText = try? String(contentsOfFile: yamlPath, encoding: .utf8)
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

    func loadBatchIntoWorkspace(_ persisted: PersistedBatch) {
        cancelAllResourceLoads()
        isRestoringWorkspace = true
        selectedAgentID = persisted.summary.agent.id
        promptTemplate = persisted.summary.promptSnapshot
        outputDirectoryPath = persisted.summary.outputDirectory
        mode = persisted.summary.mode
        parallelism = persisted.summary.parallelism
        inputText = persisted.summary.sourceInputText
        items = persisted.summary.items
        selectedItemID = persisted.summary.items.first?.id
        currentBatchID = persisted.summary.id
        currentBatchDirectory = persisted.batchDirectory.path
        validationMessage = ""
        exportMessage = ""
        progressText = ""
        completedCount = 0
        selectedYAMLText = nil
        renamingItemID = nil
        renamingTitle = ""
        renamingOriginalTitle = ""
        isRestoringWorkspace = false
        loadSelectedYAML()
        persistDraftIfNeeded()
        preloadResourcesForAllItemsIfNeeded()
    }

    private func applyDefaultWorkspaceSettings() {
        selectedAgentID = settingsViewModel.settings.selectedAgentID
        promptTemplate = settingsViewModel.settings.promptTemplate
        outputDirectoryPath = settingsViewModel.settings.outputDirectoryPath ?? batchStore.rootDirectory.path
        mode = settingsViewModel.settings.defaultGenerationMode
        parallelism = settingsViewModel.settings.parallelism
    }

    private func applyWorkspaceDraft(_ draft: GenerateWorkspaceDraft) {
        selectedAgentID = draft.selectedAgentID
        promptTemplate = draft.promptTemplate
        outputDirectoryPath = draft.outputDirectoryPath
        mode = draft.mode
        parallelism = draft.parallelism
        inputText = draft.inputText
        items = draft.items
        selectedItemID = draft.selectedItemID
        currentBatchID = draft.currentBatchID
        currentBatchDirectory = draft.currentBatchDirectory
        loadSelectedYAML()
    }

    private func persistDraftIfNeeded() {
        guard !isRestoringWorkspace else {
            return
        }
        let hasMeaningfulWorkspaceState = currentBatchID != nil
            || !items.isEmpty
            || !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasMeaningfulWorkspaceState else {
            return
        }
        persistDraft(force: false)
    }

    private func persistDraft(force: Bool) {
        guard !isRestoringWorkspace || force else {
            return
        }
        let draft = GenerateWorkspaceDraft(
            selectedAgentID: selectedAgentID,
            promptTemplate: promptTemplate,
            outputDirectoryPath: outputDirectoryPath,
            mode: mode,
            parallelism: parallelism,
            inputText: inputText,
            items: items,
            selectedItemID: selectedItemID,
            currentBatchID: currentBatchID,
            currentBatchDirectory: currentBatchDirectory
        )
        do {
            try draftStore.save(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func persistSelectedAgentToSettingsIfNeeded() {
        guard !isRestoringWorkspace else {
            return
        }
        settingsViewModel.updateSelectedAgent(selectedAgentID)
    }

    private func scheduleResourceLoad(for itemID: UUID, force: Bool) {
        if force {
            cancelResourceLoad(for: itemID)
        } else if resourceLoadTasks[itemID] != nil {
            return
        }

        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let item = items[index]
        if !force {
            if item.previewStatus == .success || item.resourceStatus == .success {
                return
            }
            if item.previewStatus == .loading || item.resourceStatus == .loading {
                return
            }
        }

        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.loadResources(for: itemID)
        }
        resourceLoadTasks[itemID] = task
    }

    private func loadResources(for itemID: UUID) async {
        defer { resourceLoadTasks[itemID] = nil }
        guard !Task.isCancelled else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let token = settingsViewModel.settings.figmaToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }

        items[index].previewStatus = .loading
        items[index].resourceStatus = .loading
        items[index].errorMessage = nil

        do {
            let resolved = try await figmaService.loadPreviewAndResources(for: items[index], token: token)
            guard !Task.isCancelled else {
                return
            }
            guard let refreshedIndex = items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            items[refreshedIndex] = resolved
        } catch {
            guard !Task.isCancelled else {
                return
            }
            guard let refreshedIndex = items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            items[refreshedIndex].previewStatus = .failed
            items[refreshedIndex].resourceStatus = .failed
            items[refreshedIndex].errorMessage = error.localizedDescription
        }
    }

    private func cancelResourceLoad(for itemID: UUID) {
        resourceLoadTasks[itemID]?.cancel()
        resourceLoadTasks[itemID] = nil
    }

    private func cancelAllResourceLoads() {
        for task in resourceLoadTasks.values {
            task.cancel()
        }
        resourceLoadTasks.removeAll()
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
    @Published var renamingBatchID: String?
    @Published var renamingBatchTitle: String = ""
    @Published var renamingOriginalBatchTitle: String = ""
    @Published var renamingItemID: UUID?
    @Published var renamingTitle: String = ""
    @Published var renamingOriginalTitle: String = ""

    private let batchStore: BatchStore
    private let continueEditing: (PersistedBatch) -> Void
    private var isSynchronizingSelection = false

    init(batchStore: BatchStore, continueEditing: @escaping (PersistedBatch) -> Void = { _ in }) {
        self.batchStore = batchStore
        self.continueEditing = continueEditing
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

    func continueEditingSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        continueEditing(batch)
    }

    func beginRenamingSelectedBatch() {
        guard let batch = selectedBatch else {
            return
        }
        renamingBatchID = batch.summary.id
        renamingBatchTitle = batch.summary.id
        renamingOriginalBatchTitle = batch.summary.id
    }

    func commitBatchRename() {
        guard let batch = selectedBatch else {
            cancelBatchRename()
            return
        }

        let trimmedTitle = renamingBatchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let persisted = try batchStore.renameBatch(id: batch.summary.id, to: trimmedTitle)
            if let index = batches.firstIndex(where: { $0.summary.id == batch.summary.id }) {
                batches[index] = persisted
            }
            selectedBatchID = persisted.summary.id
            synchronizeSelectionForCurrentBatch(resetItemSelection: false)
            message = "名称已更新"
        } catch {
            message = error.localizedDescription
        }

        cancelBatchRename()
    }

    func cancelBatchRename() {
        renamingBatchID = nil
        renamingBatchTitle = ""
        renamingOriginalBatchTitle = ""
    }

    func finishBatchRenameOnBlur() {
        guard renamingBatchID != nil else {
            return
        }
        let trimmedTitle = renamingBatchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == renamingOriginalBatchTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
            cancelBatchRename()
        } else {
            commitBatchRename()
        }
    }

    func beginRenamingSelectedItem() {
        guard let item = selectedItem else {
            return
        }
        let originalTitle = item.title ?? item.nodeName ?? item.nodeId
        renamingItemID = item.id
        renamingTitle = originalTitle
        renamingOriginalTitle = originalTitle
    }

    func commitRename() {
        guard let batch = selectedBatch,
              let item = selectedItem else {
            cancelRename()
            return
        }

        let trimmedTitle = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedItem = item
        updatedItem.title = trimmedTitle.isEmpty ? nil : trimmedTitle

        do {
            let persisted = try batchStore.updateBatchItem(batchID: batch.summary.id, item: updatedItem)
            if let index = batches.firstIndex(where: { $0.summary.id == persisted.summary.id }) {
                batches[index] = persisted
            }
            synchronizeSelectionForCurrentBatch(resetItemSelection: false)
            message = "名称已更新"
        } catch {
            message = error.localizedDescription
        }

        cancelRename()
    }

    func cancelRename() {
        renamingItemID = nil
        renamingTitle = ""
        renamingOriginalTitle = ""
    }

    func finishRenameOnBlur() {
        guard renamingItemID != nil else {
            return
        }
        let trimmedTitle = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == renamingOriginalTitle.trimmingCharacters(in: .whitespacesAndNewlines) {
            cancelRename()
        } else {
            commitRename()
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
