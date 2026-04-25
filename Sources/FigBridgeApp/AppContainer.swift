import Foundation
import SwiftUI
import FigBridgeCore

@MainActor
final class AppContainer: ObservableObject {
    @Published var settingsViewModel: SettingsViewModel
    @Published var generateViewModel: GenerateViewModel
    @Published var viewerViewModel: ViewerViewModel

    init() {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FigBridge", isDirectory: true) ?? FileManager.default.temporaryDirectory.appendingPathComponent("FigBridge", isDirectory: true)
        let batchesDirectory = baseDirectory.appendingPathComponent("Batches", isDirectory: true)
        let settingsURL = baseDirectory.appendingPathComponent("settings.json")
        let settingsStore = SettingsStore(fileURL: settingsURL)
        let batchStore = BatchStore(rootDirectory: batchesDirectory)
        let agentService = AgentService()
        let figmaService = FigmaService(baseDirectory: baseDirectory)
        let generationCoordinator = GenerationCoordinator(batchStore: batchStore, agentRunner: agentService)

        let settingsViewModel = SettingsViewModel(settingsStore: settingsStore, agentService: agentService, figmaService: figmaService)
        let generateViewModel = GenerateViewModel(settingsViewModel: settingsViewModel, batchStore: batchStore, generationCoordinator: generationCoordinator, figmaService: figmaService)
        let viewerViewModel = ViewerViewModel(batchStore: batchStore)

        self.settingsViewModel = settingsViewModel
        self.generateViewModel = generateViewModel
        self.viewerViewModel = viewerViewModel
    }
}
