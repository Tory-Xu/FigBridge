import AppKit
import Foundation
import Testing
@testable import FigBridgeApp

struct AppIconSupportTests {
    @Test func infoPlistDeclaresAppIconAndResourceLoads() throws {
        #expect(AppIconSupport.bundleIconFileName == "AppIcon")

        let iconURL = try #require(Bundle.module.url(forResource: "AppIcon", withExtension: "png"))
        #expect(FileManager.default.fileExists(atPath: iconURL.path()))

        let image = try #require(AppIconSupport.applicationIcon())
        #expect(image.isValid)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }
}
