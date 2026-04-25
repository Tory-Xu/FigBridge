import Foundation
import Testing
@testable import FigBridgeCore

struct LinkParserTests {
    @Test func parsePureURLLine() {
        let parser = FigmaLinkParser()
        let input = "@https://www.figma.com/design/FILE123/Screen?node-id=2522-8028"

        let result = parser.parse(input)

        #expect(result.items.count == 1)
        #expect(result.items[0].fileKey == "FILE123")
        #expect(result.items[0].nodeId == "2522:8028")
        #expect(result.items[0].title == nil)
        #expect(result.errors.isEmpty)
    }

    @Test func parseDescriptionLineWithChinesePunctuation() {
        let parser = FigmaLinkParser()
        let input = "首页卡片： @https://www.figma.com/design/FILE456/App?node-id=1-2"

        let result = parser.parse(input)

        #expect(result.items.count == 1)
        #expect(result.items[0].title == "首页卡片")
    }

    @Test func deduplicatesByFileKeyAndNodeId() {
        let parser = FigmaLinkParser()
        let input = """
        首页: @https://www.figma.com/design/FILE456/App?node-id=1-2
        重复链接: @https://www.figma.com/design/FILE456/App?node-id=1-2
        """

        let result = parser.parse(input)

        #expect(result.items.count == 1)
        #expect(result.errors.count == 1)
    }

    @Test func rejectsNonDesignLinkAndMissingNodeId() {
        let parser = FigmaLinkParser()
        let input = """
        @https://www.figma.com/file/FILE456/App?node-id=1-2
        @https://www.figma.com/design/FILE456/App
        """

        let result = parser.parse(input)

        #expect(result.items.isEmpty)
        #expect(result.errors.count == 2)
    }
}
