import AppKit
import Foundation

struct AppIconSupport {
    static let bundleIconFileName = "AppIcon"
    static let resourceBundleName = "FigBridge_FigBridgeApp"

    static func firstExistingResourceBundleURL(
        mainBundleURL: URL,
        resourceURL: URL?,
        executableURL: URL?,
        fileManager: FileManager
    ) -> URL? {
        let bundleFileName = "\(resourceBundleName).bundle"
        let candidates = [
            mainBundleURL.appendingPathComponent(bundleFileName, isDirectory: true),
            resourceURL?.appendingPathComponent(bundleFileName, isDirectory: true),
            executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(bundleFileName, isDirectory: true),
            executableURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(bundleFileName, isDirectory: true)
        ]

        var seenPaths = Set<String>()
        for candidate in candidates.compactMap({ $0 }) {
            let standardizedPath = candidate.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: standardizedPath, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }

        return nil
    }

    static func resourceBundle(mainBundle: Bundle = .main, fileManager: FileManager = .default) -> Bundle? {
        guard let bundleURL = firstExistingResourceBundleURL(
            mainBundleURL: mainBundle.bundleURL,
            resourceURL: mainBundle.resourceURL,
            executableURL: mainBundle.executableURL,
            fileManager: fileManager
        ) else {
            return nil
        }

        return Bundle(url: bundleURL)
    }

    static func firstAvailableIcon(from candidateBundles: [Bundle]) -> NSImage? {
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: bundleIconFileName, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }

            if let named = bundle.image(forResource: NSImage.Name(bundleIconFileName)) {
                return named
            }

            if let url = bundle.url(forResource: bundleIconFileName, withExtension: "png", subdirectory: "Assets.xcassets/AppIcon.appiconset"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }

    static func applicationIcon() -> NSImage? {
        firstAvailableIcon(from: [resourceBundle(), Bundle.main].compactMap { $0 })
    }
}
