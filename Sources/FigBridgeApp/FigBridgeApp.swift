import SwiftUI
import FigBridgeCore
import AppKit

final class FigBridgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let icon = AppIconSupport.applicationIcon() {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct FigBridgeApp: App {
    @NSApplicationDelegateAdaptor(FigBridgeAppDelegate.self) private var appDelegate
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
