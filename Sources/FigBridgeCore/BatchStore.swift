import Foundation

public final class BatchStore: Sendable {
    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static let exportsDirectoryName = "exports"

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func createBatch(_ batch: GenerationBatch) throws -> PersistedBatch {
        try ensureRootDirectoryExists()
        let batchDirectory = rootDirectory.appendingPathComponent(batch.id, isDirectory: true)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        return try writeBatch(batch, into: batchDirectory)
    }

    public func batchDirectory(for id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    public func exportsDirectory(forBatchID id: String) -> URL {
        exportsDirectory(for: batchDirectory(for: id))
    }

    public func exportsDirectory(for batchDirectory: URL) -> URL {
        batchDirectory.appendingPathComponent(Self.exportsDirectoryName, isDirectory: true)
    }

    public func loadBatch(id: String) throws -> PersistedBatch? {
        let batchDirectory = batchDirectory(for: id)
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            return nil
        }
        return try loadBatch(at: batchDirectory)
    }

    public func updateBatch(
        id: String,
        sourceInputText: String,
        agent: AgentProvider,
        promptSnapshot: String,
        outputDirectory: URL,
        mode: GenerationMode,
        parallelism: Int,
        callStrategy: AgentCallStrategy,
        items: [FigmaLinkItem]
    ) throws -> PersistedBatch {
        let batchDirectory = batchDirectory(for: id)
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let existing = try loadBatch(at: batchDirectory)
        let batch = GenerationBatch(
            id: existing.summary.id,
            createdAt: existing.summary.createdAt,
            agent: agent,
            promptSnapshot: promptSnapshot,
            sourceInputText: sourceInputText,
            outputDirectory: outputDirectory.path,
            mode: mode,
            parallelism: parallelism,
            callStrategy: callStrategy,
            items: items
        )
        return try writeBatch(batch, into: batchDirectory)
    }

    public func deleteBatchItem(batchID: String, itemID: UUID) throws {
        guard let persisted = try loadBatch(id: batchID) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let updatedItems = persisted.summary.items.filter { $0.id != itemID }
        guard updatedItems.count != persisted.summary.items.count else {
            return
        }

        if let itemDirectory = itemDirectory(in: persisted.batchDirectory, itemID: itemID),
           FileManager.default.fileExists(atPath: itemDirectory.path) {
            try FileManager.default.removeItem(at: itemDirectory)
        }

        _ = try updateBatch(
            id: batchID,
            sourceInputText: persisted.summary.sourceInputText,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: persisted.summary.outputDirectory, isDirectory: true),
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: updatedItems
        )
    }

    public func updateBatchItem(batchID: String, item: FigmaLinkItem) throws -> PersistedBatch {
        guard let persisted = try loadBatch(id: batchID) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        var updatedItems = persisted.summary.items
        guard let index = updatedItems.firstIndex(where: { $0.id == item.id }) else {
            return persisted
        }
        updatedItems[index] = item
        return try updateBatch(
            id: batchID,
            sourceInputText: persisted.summary.sourceInputText,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            outputDirectory: URL(fileURLWithPath: persisted.summary.outputDirectory, isDirectory: true),
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: updatedItems
        )
    }

    public func renameBatch(id: String, to newID: String) throws -> PersistedBatch {
        guard let persisted = try loadBatch(id: id) else {
            throw BatchStoreError.invalidBatchDirectory
        }

        let trimmedID = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw BatchStoreError.invalidBatchName
        }
        guard trimmedID != id else {
            return persisted
        }

        try ensureRootDirectoryExists()
        let destinationDirectory = rootDirectory.appendingPathComponent(trimmedID, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destinationDirectory.path) else {
            throw BatchStoreError.batchAlreadyExists
        }

        try FileManager.default.moveItem(at: persisted.batchDirectory, to: destinationDirectory)

        let renamedBatch = GenerationBatch(
            id: trimmedID,
            createdAt: persisted.summary.createdAt,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            sourceInputText: persisted.summary.sourceInputText,
            outputDirectory: persisted.summary.outputDirectory,
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: persisted.summary.items
        )
        return try writeBatch(renamedBatch, into: destinationDirectory)
    }

    public func scanBatches() throws -> [PersistedBatch] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try directories.compactMap { url in
            let batchURL = url.appendingPathComponent("batch.json")
            guard FileManager.default.fileExists(atPath: batchURL.path) else {
                return nil
            }
            return try loadBatch(at: url)
        }
        .sorted { $0.summary.createdAt > $1.summary.createdAt }
    }

    public func makeCopyPrompt(for items: [FigmaLinkItem]) -> String {
        let yamlPaths = items.compactMap(\.generatedYAMLPath)
        return (["Implement this design from yaml files."] + yamlPaths).joined(separator: "\n")
    }

    public func exportBatch(at batchDirectory: URL, to destinationURL: URL) throws -> BatchExportResult {
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let persisted = try loadBatch(at: batchDirectory)
        let missingPaths = collectMissingImagePaths(in: persisted.summary)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destinationURL.path, batchDirectory.lastPathComponent]
        process.currentDirectoryURL = batchDirectory.deletingLastPathComponent()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BatchStoreError.exportFailed
        }
        return BatchExportResult(
            archiveURL: destinationURL,
            missingPreviewPaths: missingPaths.previews,
            missingResourcePaths: missingPaths.resources
        )
    }

    public func importBatchDirectory(from sourceDirectory: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        try ensureRootDirectoryExists()
        let destinationURL = uniqueImportedDirectoryName(for: sourceDirectory.lastPathComponent)
        try FileManager.default.copyItem(at: sourceDirectory, to: destinationURL)
        try rewriteImportedBatchID(at: destinationURL, to: destinationURL.lastPathComponent)
        return destinationURL
    }

    public func importBatchArchive(from archiveURL: URL) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", tempDirectory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BatchStoreError.importFailed
        }

        let entries = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard let batchDirectory = entries.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("batch.json").path)
        }) else {
            throw BatchStoreError.invalidBatchDirectory
        }

        try ensureRootDirectoryExists()
        let destinationURL = uniqueImportedDirectoryName(for: batchDirectory.lastPathComponent)
        try FileManager.default.copyItem(at: batchDirectory, to: destinationURL)
        try rewriteImportedBatchID(at: destinationURL, to: destinationURL.lastPathComponent)
        return destinationURL
    }

    public func deleteBatch(at batchDirectory: URL) throws {
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        try FileManager.default.removeItem(at: batchDirectory)
    }

    public func copyFileToDirectory(_ sourceURL: URL, destinationDirectory: URL, preferredName: String? = nil) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BatchStoreError.sourceFileMissing
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let baseName = preferredName ?? sourceURL.lastPathComponent
        let destinationURL = uniqueFileURL(in: destinationDirectory, preferredName: baseName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func slug(for value: String) -> String {
        let lowercase = value.lowercased()
        let mapped = lowercase.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let string = String(mapped)
        let collapsed = string.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func uniqueImportedDirectoryName(for baseName: String) -> URL {
        let primaryCandidate = rootDirectory.appendingPathComponent(baseName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: primaryCandidate.path) else {
            return primaryCandidate
        }

        var index = 2
        while true {
            let candidate = rootDirectory.appendingPathComponent("\(baseName)(\(index))", isDirectory: true)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func uniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let candidate = directory.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 2
        while true {
            let filename = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let next = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: next.path) {
                return next
            }
            index += 1
        }
    }

    private func ensureRootDirectoryExists() throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func rewriteImportedBatchID(at batchDirectory: URL, to batchID: String) throws {
        let persisted = try loadBatch(at: batchDirectory)
        let updatedBatch = GenerationBatch(
            id: batchID,
            createdAt: persisted.summary.createdAt,
            agent: persisted.summary.agent,
            promptSnapshot: persisted.summary.promptSnapshot,
            sourceInputText: persisted.summary.sourceInputText,
            outputDirectory: persisted.summary.outputDirectory,
            mode: persisted.summary.mode,
            parallelism: persisted.summary.parallelism,
            callStrategy: persisted.summary.callStrategy,
            items: persisted.summary.items
        )
        _ = try writeBatch(updatedBatch, into: batchDirectory)
    }

    private func writeBatch(_ batch: GenerationBatch, into batchDirectory: URL) throws -> PersistedBatch {
        let sourceInputURL = batchDirectory.appendingPathComponent("source-input.txt")
        try batch.sourceInputText.write(to: sourceInputURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: exportsDirectory(for: batchDirectory), withIntermediateDirectories: true)

        let itemsDirectory = batchDirectory.appendingPathComponent("items", isDirectory: true)
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)

        let archivedBatch = try archiveBatchAssetsIfNeeded(batch, batchDirectory: batchDirectory, itemsDirectory: itemsDirectory)
        let existingDirectories = existingItemDirectoryMap(in: itemsDirectory)
        let validDirectoryNames = Set(archivedBatch.items.map { directoryName(for: $0) })

        for (name, url) in existingDirectories where !validDirectoryNames.contains(name) {
            try? FileManager.default.removeItem(at: url)
        }

        var itemDirectories: [URL] = []
        for item in archivedBatch.items {
            let itemDirectory = itemsDirectory.appendingPathComponent(directoryName(for: item), isDirectory: true)
            try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            let metaURL = itemDirectory.appendingPathComponent("meta.json")
            let data = try encoder.encode(makePersistable(item: item, batchDirectory: batchDirectory))
            try data.write(to: metaURL)
            itemDirectories.append(itemDirectory)
        }

        let batchURL = batchDirectory.appendingPathComponent("batch.json")
        let batchData = try encoder.encode(makePersistable(batch: archivedBatch, batchDirectory: batchDirectory))
        try batchData.write(to: batchURL)

        return PersistedBatch(summary: makeRuntimeBatch(from: archivedBatch, batchDirectory: batchDirectory), batchDirectory: batchDirectory, itemDirectories: itemDirectories)
    }

    private func loadBatch(at directory: URL) throws -> PersistedBatch {
        let batchURL = directory.appendingPathComponent("batch.json")
        let data = try Data(contentsOf: batchURL)
        let batch = makeRuntimeBatch(from: try decoder.decode(GenerationBatch.self, from: data), batchDirectory: directory)
        let itemDirectories = batch.items.compactMap { itemDirectory(in: directory, itemID: $0.id) }
        return PersistedBatch(summary: batch, batchDirectory: directory, itemDirectories: itemDirectories)
    }

    private func existingItemDirectoryMap(in itemsDirectory: URL) -> [String: URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, $0) })
    }

    private func directoryName(for item: FigmaLinkItem) -> String {
        "\(item.id.uuidString.lowercased())-\(item.nodeId.replacingOccurrences(of: ":", with: "-"))"
    }

    private func itemDirectory(in batchDirectory: URL, itemID: UUID) -> URL? {
        let itemsDirectory = batchDirectory.appendingPathComponent("items", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        let prefix = itemID.uuidString.lowercased()
        return entries.first(where: { $0.lastPathComponent.hasPrefix(prefix) })
    }

    private func archiveBatchAssetsIfNeeded(_ batch: GenerationBatch, batchDirectory: URL, itemsDirectory: URL) throws -> GenerationBatch {
        var archivedBatch = batch
        archivedBatch.items = try batch.items.map { item in
            let itemDirectory = itemsDirectory.appendingPathComponent(directoryName(for: item), isDirectory: true)
            return try archiveItemAssetsIfNeeded(item, batchDirectory: batchDirectory, itemDirectory: itemDirectory)
        }
        return archivedBatch
    }

    private func archiveItemAssetsIfNeeded(_ item: FigmaLinkItem, batchDirectory: URL, itemDirectory: URL) throws -> FigmaLinkItem {
        var archivedItem = item
        let assetsDirectory = itemDirectory.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        archivedItem.previewImagePath = try archiveLocalAssetIfNeeded(
            item.previewImagePath,
            batchDirectory: batchDirectory,
            destinationDirectory: assetsDirectory,
            preferredName: "preview.png"
        )

        archivedItem.resourceItems = try item.resourceItems.map { resource in
            var updated = resource
            let fallbackName = resource.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "\(resource.name).\(resource.format.rawValue)"
            updated.localPath = try archiveLocalAssetIfNeeded(
                resource.localPath,
                batchDirectory: batchDirectory,
                destinationDirectory: assetsDirectory,
                preferredName: fallbackName
            )
            return updated
        }

        return archivedItem
    }

    private func archiveLocalAssetIfNeeded(
        _ path: String?,
        batchDirectory: URL,
        destinationDirectory: URL,
        preferredName: String
    ) throws -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
        let batchPath = batchDirectory.standardizedFileURL.path
        let sourcePath = sourceURL.path
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return path
        }

        if sourcePath == batchPath || sourcePath.hasPrefix(batchPath + "/") {
            return sourcePath
        }

        let destinationURL = destinationDirectory.appendingPathComponent(preferredName).standardizedFileURL
        if sourcePath == destinationURL.path {
            return destinationURL.path
        }

        let resolvedDestinationURL: URL
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let existingData = try? Data(contentsOf: destinationURL)
            let sourceData = try? Data(contentsOf: sourceURL)
            if existingData == sourceData {
                resolvedDestinationURL = destinationURL
            } else {
                resolvedDestinationURL = uniqueFileURL(in: destinationDirectory, preferredName: preferredName)
            }
        } else {
            resolvedDestinationURL = destinationURL
        }

        if !FileManager.default.fileExists(atPath: resolvedDestinationURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: resolvedDestinationURL)
        }
        return resolvedDestinationURL.path
    }

    private func makePersistable(batch: GenerationBatch, batchDirectory: URL) -> GenerationBatch {
        var persisted = batch
        persisted.outputDirectory = relativizePath(batch.outputDirectory, batchDirectory: batchDirectory) ?? Self.exportsDirectoryName
        persisted.items = batch.items.map { makePersistable(item: $0, batchDirectory: batchDirectory) }
        return persisted
    }

    private func makePersistable(item: FigmaLinkItem, batchDirectory: URL) -> FigmaLinkItem {
        var persisted = item
        persisted.previewImagePath = relativizePath(item.previewImagePath, batchDirectory: batchDirectory)
        persisted.generatedYAMLPath = relativizePath(item.generatedYAMLPath, batchDirectory: batchDirectory)
        persisted.agentOutputPath = relativizePath(item.agentOutputPath, batchDirectory: batchDirectory)
        persisted.resourceItems = item.resourceItems.map { resource in
            var updated = resource
            updated.localPath = relativizePath(resource.localPath, batchDirectory: batchDirectory)
            return updated
        }
        return persisted
    }

    private func makeRuntimeBatch(from batch: GenerationBatch, batchDirectory: URL) -> GenerationBatch {
        var runtime = batch
        runtime.outputDirectory = absolutizePath(batch.outputDirectory, batchDirectory: batchDirectory) ?? exportsDirectory(for: batchDirectory).path
        runtime.items = batch.items.map { makeRuntimeItem(from: $0, batchDirectory: batchDirectory) }
        return runtime
    }

    private func makeRuntimeItem(from item: FigmaLinkItem, batchDirectory: URL) -> FigmaLinkItem {
        var runtime = item
        runtime.previewImagePath = absolutizePath(item.previewImagePath, batchDirectory: batchDirectory)
        runtime.generatedYAMLPath = absolutizePath(item.generatedYAMLPath, batchDirectory: batchDirectory)
        runtime.agentOutputPath = absolutizePath(item.agentOutputPath, batchDirectory: batchDirectory)
        runtime.resourceItems = item.resourceItems.map { resource in
            var updated = resource
            updated.localPath = absolutizePath(resource.localPath, batchDirectory: batchDirectory)
            return updated
        }
        return runtime
    }

    private func relativizePath(_ path: String?, batchDirectory: URL) -> String? {
        guard let path else {
            return nil
        }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let basePath = batchDirectory.standardizedFileURL.path
        guard standardizedPath == basePath || standardizedPath.hasPrefix(basePath + "/") else {
            return path
        }
        let relative = String(standardizedPath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }

    private func absolutizePath(_ path: String?, batchDirectory: URL) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }
        if path == "." {
            return batchDirectory.path
        }
        if path.hasPrefix("/") {
            return path
        }
        return batchDirectory.appendingPathComponent(path).path
    }

    private func collectMissingImagePaths(in batch: GenerationBatch) -> (previews: [String], resources: [String]) {
        let missingPreviews = batch.items.compactMap { item -> String? in
            guard let path = item.previewImagePath else {
                return nil
            }
            return FileManager.default.fileExists(atPath: path) ? nil : path
        }

        let missingResources = batch.items.flatMap { item in
            item.resourceItems.compactMap { resource -> String? in
                guard let path = resource.localPath else {
                    return nil
                }
                return FileManager.default.fileExists(atPath: path) ? nil : path
            }
        }

        return (missingPreviews, missingResources)
    }
}

public enum BatchStoreError: LocalizedError {
    case invalidBatchDirectory
    case invalidBatchName
    case batchAlreadyExists
    case exportFailed
    case importFailed
    case sourceFileMissing

    public var errorDescription: String? {
        switch self {
        case .invalidBatchDirectory:
            "批次目录缺少 batch.json"
        case .invalidBatchName:
            "批次名称不能为空"
        case .batchAlreadyExists:
            "批次名称已存在"
        case .exportFailed:
            "导出批次失败"
        case .importFailed:
            "导入批次失败"
        case .sourceFileMissing:
            "源文件不存在"
        }
    }
}
