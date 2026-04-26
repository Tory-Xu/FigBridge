import Foundation
import Testing
@testable import FigBridgeCore

struct BatchZipImportTests {
    @Test func importsZipArchiveIntoUniqueBatchDirectory() throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let store = BatchStore(rootDirectory: sandbox.root.appendingPathComponent("store"))

        let sourceRoot = sandbox.root.appendingPathComponent("source")
        let batchDirectory = sourceRoot.appendingPathComponent("batch-one")
        try FileManager.default.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
        let batchJSON = """
        {
          "agent" : "codex",
          "callStrategy" : "singlePerLink",
          "createdAt" : "1970-01-01T00:00:00Z",
          "id" : "batch-one",
          "items" : [ ],
          "mode" : "sequential",
          "outputDirectory" : "\(batchDirectory.path)",
          "parallelism" : 2,
          "promptSnapshot" : "prompt",
          "sourceInputText" : "input"
        }
        """
        try batchJSON.write(to: batchDirectory.appendingPathComponent("batch.json"), atomically: true, encoding: .utf8)

        let zipURL = sandbox.root.appendingPathComponent("batch-one.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", zipURL.path, "batch-one"]
        process.currentDirectoryURL = sourceRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let imported = try store.importBatchArchive(from: zipURL)
        let importedAgain = try store.importBatchArchive(from: zipURL)

        #expect(imported.lastPathComponent == "batch-one")
        #expect(importedAgain.lastPathComponent == "batch-one(2)")
        #expect(FileManager.default.fileExists(atPath: store.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: imported.appendingPathComponent("batch.json").path))

        let importedAgainBatch = try #require(try store.loadBatch(id: "batch-one(2)"))
        #expect(importedAgainBatch.summary.id == "batch-one(2)")
    }
}
