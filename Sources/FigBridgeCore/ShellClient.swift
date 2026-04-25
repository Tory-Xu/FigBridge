import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct ShellClient: Sendable {
    public let pathLookupDirectories: [URL]
    public let environment: [String: String]

    public init(pathLookupDirectories: [URL] = [], environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.pathLookupDirectories = pathLookupDirectories
        self.environment = environment
    }

    public func resolveExecutable(named name: String) -> URL? {
        for directory in searchDirectories() {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func run(executable: URL, arguments: [String]) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = executable
            task.arguments = arguments
            task.environment = runtimeEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            do {
                try task.run()
                task.terminationHandler = { process in
                    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(returning: ShellResult(status: process.terminationStatus, stdout: stdout, stderr: stderr))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func searchDirectories() -> [URL] {
        var orderedDirectories: [URL] = []
        var visitedPaths = Set<String>()

        func appendDirectory(_ url: URL) {
            let normalizedPath = url.standardizedFileURL.path
            guard !normalizedPath.isEmpty, !visitedPaths.contains(normalizedPath) else {
                return
            }
            visitedPaths.insert(normalizedPath)
            orderedDirectories.append(url)
        }

        for directory in pathLookupDirectories {
            appendDirectory(directory)
        }

        let pathComponents = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for path in pathComponents where !path.isEmpty {
            appendDirectory(URL(fileURLWithPath: path, isDirectory: true))
        }

        if let home = environment["HOME"], !home.isEmpty {
            let homeURL = URL(fileURLWithPath: home, isDirectory: true)
            let homeFallbacks = [
                ".superconductor/bin",
                ".local/bin",
                ".cargo/bin",
                ".bun/bin",
                ".opencode/bin",
                ".codex/bin",
                ".npm-global/bin"
            ]
            for relativePath in homeFallbacks {
                appendDirectory(homeURL.appendingPathComponent(relativePath, isDirectory: true))
            }
        }

        let systemFallbacks = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin"
        ]
        for path in systemFallbacks {
            appendDirectory(URL(fileURLWithPath: path, isDirectory: true))
        }

        return orderedDirectories
    }

    private func runtimeEnvironment() -> [String: String] {
        var merged = environment
        let path = searchDirectories().map(\.path).joined(separator: ":")
        if !path.isEmpty {
            merged["PATH"] = path
        }
        return merged
    }
}
