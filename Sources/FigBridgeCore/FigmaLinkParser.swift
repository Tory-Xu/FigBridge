import Foundation

public struct FigmaLinkParser {
    public init() {}

    public func parse(_ input: String) -> ParsedLinkResult {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        var items: [FigmaLinkItem] = []
        var errors: [String] = []
        var dedupe = Set<String>()

        for (index, line) in lines.enumerated() {
            let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLine.isEmpty else {
                continue
            }
            guard let url = firstFigmaURL(in: rawLine) else {
                continue
            }

            do {
                let parsed = try parseURL(url)
                let dedupeKey = "\(parsed.fileKey)|\(parsed.nodeId)"
                guard !dedupe.contains(dedupeKey) else {
                    errors.append("line \(index + 1): 重复 fileKey + nodeId")
                    continue
                }
                dedupe.insert(dedupeKey)
                let title = extractTitle(from: rawLine, url: url)
                items.append(
                    FigmaLinkItem(
                        rawInputLine: rawLine,
                        title: title,
                        url: url,
                        fileKey: parsed.fileKey,
                        nodeId: parsed.nodeId
                    )
                )
            } catch {
                errors.append("line \(index + 1): \(error.localizedDescription)")
            }
        }

        return ParsedLinkResult(items: items, errors: errors)
    }

    public func parseURL(_ rawURL: String) throws -> (fileKey: String, nodeId: String) {
        let cleanURL = rawURL.hasPrefix("@") ? String(rawURL.dropFirst()) : rawURL
        guard cleanURL.contains("https://www.figma.com/design/") else {
            throw FigmaLinkParserError.unsupportedLink
        }
        guard let url = URL(string: cleanURL) else {
            throw FigmaLinkParserError.invalidLink
        }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, components[0] == "design" else {
            throw FigmaLinkParserError.invalidLink
        }
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let nodeID = queryItems.first(where: { $0.name == "node-id" })?.value,
              !nodeID.isEmpty else {
            throw FigmaLinkParserError.missingNodeID
        }

        return (components[1], nodeID.replacingOccurrences(of: "-", with: ":"))
    }

    private func firstFigmaURL(in line: String) -> String? {
        guard let range = line.range(of: "@https://www.figma.com/") ?? line.range(of: "https://www.figma.com/") else {
            return nil
        }
        let candidate = String(line[range.lowerBound...])
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,；;）)】]"))
        let scalars = candidate.unicodeScalars.prefix { !terminators.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func extractTitle(from line: String, url: String) -> String? {
        let cleanedURL = url.hasPrefix("@") ? String(url.dropFirst()) : url
        let prefix = line.replacingOccurrences(of: "@\(cleanedURL)", with: "").replacingOccurrences(of: cleanedURL, with: "")
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":："))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum FigmaLinkParserError: LocalizedError {
    case unsupportedLink
    case invalidLink
    case missingNodeID

    public var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            "仅支持 figma design 链接"
        case .invalidLink:
            "figma 链接格式不合法"
        case .missingNodeID:
            "缺少 node-id 参数"
        }
    }
}
