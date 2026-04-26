import Foundation
import FigBridgeCore

struct GenerateWorkspaceDraft: Codable, Equatable {
    var selectedAgentID: String?
    var promptTemplate: String
    var outputDirectoryPath: String
    var mode: GenerationMode
    var parallelism: Int
    var inputText: String
    var items: [FigmaLinkItem]
    var selectedItemID: UUID?
    var currentBatchID: String?
    var currentBatchDirectory: String?
}

final class GenerateWorkspaceDraftStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func load() -> GenerateWorkspaceDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(GenerateWorkspaceDraft.self, from: data)
    }

    func save(_ draft: GenerateWorkspaceDraft) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(draft)
        try data.write(to: fileURL)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}
