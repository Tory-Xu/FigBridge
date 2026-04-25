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
        for directory in pathLookupDirectories {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let pathComponents = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for path in pathComponents {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(name)
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
            task.environment = environment

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
}
