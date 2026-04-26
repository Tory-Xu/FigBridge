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

public enum ShellEvent: Equatable, Sendable {
    case started(pid: Int32)
    case stdout(String)
    case stderr(String)
    case finished(status: Int32)
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
        try await runStreaming(executable: executable, arguments: arguments, onEvent: nil)
    }

    public func runStreaming(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval? = nil,
        onEvent: (@Sendable (ShellEvent) async -> Void)?
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = executable
            task.arguments = arguments
            task.environment = runtimeEnvironment()

            let stdinHandle = FileHandle(forReadingAtPath: "/dev/null")
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            task.standardInput = stdinHandle
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe
            let stdoutCollector = StreamCollector()
            let stderrCollector = StreamCollector()
            let resumeBox = ContinuationResumeBox()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }
                stdoutCollector.append(data: data)
                if let text = String(data: data, encoding: .utf8), !text.isEmpty, let onEvent {
                    Task {
                        await onEvent(.stdout(text))
                    }
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }
                stderrCollector.append(data: data)
                if let text = String(data: data, encoding: .utf8), !text.isEmpty, let onEvent {
                    Task {
                        await onEvent(.stderr(text))
                    }
                }
            }

            do {
                try task.run()
                if let onEvent {
                    Task {
                        await onEvent(.started(pid: task.processIdentifier))
                    }
                }
                task.terminationHandler = { process in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    try? stdinHandle?.close()
                    let stdoutTail = stdoutPipe.fileHandleForReading.availableData
                    let stderrTail = stderrPipe.fileHandleForReading.availableData
                    stdoutCollector.append(data: stdoutTail)
                    stderrCollector.append(data: stderrTail)
                    if let text = String(data: stdoutTail, encoding: .utf8), !text.isEmpty, let onEvent {
                        Task {
                            await onEvent(.stdout(text))
                        }
                    }
                    if let text = String(data: stderrTail, encoding: .utf8), !text.isEmpty, let onEvent {
                        Task {
                            await onEvent(.stderr(text))
                        }
                    }
                    if let onEvent {
                        Task {
                            await onEvent(.finished(status: process.terminationStatus))
                        }
                    }
                    resumeBox.resume {
                        continuation.resume(returning: ShellResult(status: process.terminationStatus, stdout: stdoutCollector.fullText(), stderr: stderrCollector.fullText()))
                    }
                }
                if let timeout, timeout > 0 {
                    Task.detached {
                        try? await Task.sleep(for: .seconds(timeout))
                        guard task.isRunning else {
                            return
                        }
                        task.terminate()
                    }
                }
            } catch {
                resumeBox.resume {
                    continuation.resume(throwing: error)
                }
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

private final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(data: Data) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func fullText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}

private final class ContinuationResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else {
            return
        }
        didResume = true
        body()
    }
}
