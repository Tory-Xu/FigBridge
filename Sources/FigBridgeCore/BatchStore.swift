import Foundation

public final class BatchStore: Sendable {
    public let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func createBatch(_ batch: GenerationBatch) throws -> PersistedBatch {
        let batchDirectory = rootDirectory.appendingPathComponent(batch.id, isDirectory: true)
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        let sourceInputURL = batchDirectory.appendingPathComponent("source-input.txt")
        try batch.sourceInputText.write(to: sourceInputURL, atomically: true, encoding: .utf8)

        var itemDirectories: [URL] = []
        let itemsDirectory = batchDirectory.appendingPathComponent("items", isDirectory: true)
        try FileManager.default.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)

        for (index, item) in batch.items.enumerated() {
            let itemDirectory = itemsDirectory.appendingPathComponent("\(String(format: "%02d", index + 1))-\(slug(for: item.nodeName ?? item.nodeId))", isDirectory: true)
            try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            let metaURL = itemDirectory.appendingPathComponent("meta.json")
            let data = try encoder.encode(item)
            try data.write(to: metaURL)
            itemDirectories.append(itemDirectory)
        }

        let batchURL = batchDirectory.appendingPathComponent("batch.json")
        let batchData = try encoder.encode(batch)
        try batchData.write(to: batchURL)

        return PersistedBatch(summary: batch, batchDirectory: batchDirectory, itemDirectories: itemDirectories)
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
            let data = try Data(contentsOf: batchURL)
            let batch = try decoder.decode(GenerationBatch.self, from: data)

            let itemsDirectory = url.appendingPathComponent("items")
            let itemDirectories = (try? FileManager.default.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil)) ?? []
            return PersistedBatch(summary: batch, batchDirectory: url, itemDirectories: itemDirectories)
        }
        .sorted { $0.summary.createdAt > $1.summary.createdAt }
    }

    public func makeCopyPrompt(for items: [FigmaLinkItem]) -> String {
        let yamlPaths = items.compactMap(\.generatedYAMLPath)
        return (["Implement this design from yaml files."] + yamlPaths).joined(separator: "\n")
    }

    public func exportBatch(at batchDirectory: URL, to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: batchDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destinationURL.path, batchDirectory.lastPathComponent]
        process.currentDirectoryURL = batchDirectory.deletingLastPathComponent()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BatchStoreError.exportFailed
        }
    }

    public func importBatchDirectory(from sourceDirectory: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("batch.json").path) else {
            throw BatchStoreError.invalidBatchDirectory
        }
        let destinationURL = uniqueImportedDirectoryName(for: sourceDirectory.lastPathComponent)
        try FileManager.default.copyItem(at: sourceDirectory, to: destinationURL)
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

        let destinationName = preferredImportedName(for: batchDirectory.lastPathComponent)
        let destinationURL = uniqueImportedDirectoryName(for: destinationName, appendImportedSuffix: false)
        try FileManager.default.copyItem(at: batchDirectory, to: destinationURL)
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

    private func preferredImportedName(for baseName: String) -> String {
        let primaryCandidate = rootDirectory.appendingPathComponent(baseName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: primaryCandidate.path) {
            return baseName
        }
        return "\(baseName)-imported"
    }

    private func uniqueImportedDirectoryName(for baseName: String, appendImportedSuffix: Bool = true) -> URL {
        let firstName = appendImportedSuffix ? "\(baseName)-imported" : baseName
        let firstCandidate = rootDirectory.appendingPathComponent(firstName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: firstCandidate.path) else {
            return firstCandidate
        }

        var index = 2
        while true {
            let candidate = rootDirectory.appendingPathComponent("\(firstName)-\(index)", isDirectory: true)
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
}

public enum BatchStoreError: LocalizedError {
    case invalidBatchDirectory
    case exportFailed
    case importFailed
    case sourceFileMissing

    public var errorDescription: String? {
        switch self {
        case .invalidBatchDirectory:
            "批次目录缺少 batch.json"
        case .exportFailed:
            "导出批次失败"
        case .importFailed:
            "导入批次失败"
        case .sourceFileMissing:
            "源文件不存在"
        }
    }
}
