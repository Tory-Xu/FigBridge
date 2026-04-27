import AppKit
import Foundation
import Testing
@testable import FigBridgeApp

struct AppIconSupportTests {
    @Test func resourceBundleLocatorFindsBundleInAppResources() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let appBundleURL = tempDirectory.appendingPathComponent("FigBridge.app", isDirectory: true)
        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let bundleURL = resourcesURL.appendingPathComponent("\(AppIconSupport.resourceBundleName).bundle", isDirectory: true)

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let resolvedURL = AppIconSupport.firstExistingResourceBundleURL(
            mainBundleURL: appBundleURL,
            resourceURL: resourcesURL,
            executableURL: contentsURL.appendingPathComponent("MacOS/FigBridge"),
            fileManager: .default
        )

        #expect(resolvedURL == bundleURL)
    }

    @Test func infoPlistDeclaresAppIconAndResourceLoads() throws {
        #expect(AppIconSupport.bundleIconFileName == "AppIcon")

        let iconURL = try #require(Bundle.module.url(forResource: "AppIcon", withExtension: "png"))
        #expect(FileManager.default.fileExists(atPath: iconURL.path()))

        let image = try #require(AppIconSupport.firstAvailableIcon(from: [Bundle.module]))
        #expect(image.isValid)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
