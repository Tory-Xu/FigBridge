import SwiftUI
import FigBridgeCore

@main
struct FigBridgeApp: App {
    @StateObject private var appContainer = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appContainer)
                .frame(minWidth: 1280, minHeight: 820)
        }
        .windowResizability(.contentSize)
    }
}
