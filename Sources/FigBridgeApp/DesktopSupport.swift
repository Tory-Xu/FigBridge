import AppKit
import Foundation

enum DesktopSupport {
    @MainActor
    static func chooseDirectory(canCreateDirectories: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreateDirectories
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseZipArchive() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    static func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
