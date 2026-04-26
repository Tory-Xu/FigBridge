import AppKit
import Foundation

struct AppIconSupport {
    static let bundleIconFileName = "AppIcon"

    static func applicationIcon() -> NSImage? {
        if let url = Bundle.module.url(forResource: bundleIconFileName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let named = Bundle.module.image(forResource: NSImage.Name(bundleIconFileName)) {
            return named
        }

        if let url = Bundle.module.url(forResource: bundleIconFileName, withExtension: "png", subdirectory: "Assets.xcassets/AppIcon.appiconset") {
            return NSImage(contentsOf: url)
        }

        return nil
    }
}
