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
        #expect(plist["LSMinimumSystemVersion"] as? String == "12.0")
    }

    @Test func packageScriptSupportsDualArchitectureDmgOutputs() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/package-dmg.sh")

        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("TARGET_ARCH=\"${1:-arm64}\""))
        #expect(script.contains("arm64|x86_64"))
        #expect(script.contains("swift build -c \"$CONFIGURATION\" --arch \"$TARGET_ARCH\""))
        #expect(script.contains("DMG_PATH=\"$DIST_DIR/$APP_NAME-$TARGET_ARCH.dmg\""))
        #expect(script.contains("expected 12.0"))
    }
}
