import Foundation
import Testing

struct PackagingMetadataTests {
    @Test func infoPlistContainsBundleMetadataRequiredForPackaging() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FigBridgeApp/Resources/Info.plist")

        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        #expect(plist["CFBundleDisplayName"] as? String == "FigBridge")
        #expect(plist["CFBundleIdentifier"] as? String == "com.xuxuxu.figbridge")
        #expect(plist["CFBundleName"] as? String == "FigBridge")
        #expect(plist["CFBundleShortVersionString"] as? String == "1.0")
        #expect(plist["CFBundleVersion"] as? String == "1")
        #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
    }
}
