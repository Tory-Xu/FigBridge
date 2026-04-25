import Foundation
import Testing
@testable import FigBridgeCore

struct BatchStoreMaintenanceTests {
    @Test func deletesBatchDirectory() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let batchDirectory = sandbox.root.appendingPathComponent("batch-delete")
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        try "{}".write(to: batchDirectory.appendingPathComponent("batch.json"), atomically: true, encoding: .utf8)

        try store.deleteBatch(at: batchDirectory)

        #expect(!FileManager.default.fileExists(atPath: batchDirectory.path))
    }

    @Test func copiesResourceToTargetDirectoryWithStableName() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root)
        let sourceFile = sandbox.root.appendingPathComponent("preview.png")
        try Data("png".utf8).write(to: sourceFile)
        let destinationDirectory = sandbox.root.appendingPathComponent("exports")

        let copiedURL = try store.copyFileToDirectory(sourceFile, destinationDirectory: destinationDirectory, preferredName: "node-preview.png")

        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        #expect(copiedURL.lastPathComponent == "node-preview.png")
    }
}
