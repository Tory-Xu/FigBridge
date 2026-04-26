import Foundation

public enum AgentServiceError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(String)
    case emptyOutput
    case executionTimedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "未找到可执行 agent: \(name)"
        case .executionFailed(let message):
            message
        case .emptyOutput:
            "agent 输出为空"
        case .executionTimedOut(let seconds):
            "agent 执行超时（\(Int(seconds)) 秒）"
        }
    }
}

public struct AgentRunResult: Sendable {
    public let output: String
    public let executablePath: String
    public let arguments: [String]
    public let exitCode: Int32
    public let stderr: String

    public init(output: String, executablePath: String, arguments: [String], exitCode: Int32 = 0, stderr: String = "") {
        self.output = output
        self.executablePath = executablePath
        self.arguments = arguments
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

public struct AgentService: Sendable {
    public let shellClient: ShellClient
    public let executionTimeout: TimeInterval

    public init(shellClient: ShellClient = ShellClient(), executionTimeout: TimeInterval = 300) {
        self.shellClient = shellClient
        self.executionTimeout = executionTimeout
    }

    public func detectAvailableAgents() async throws -> [AgentDescriptor] {
        var agents: [AgentDescriptor] = []
        for provider in AgentProvider.allCases {
            if let descriptor = try await detect(provider: provider) {
                agents.append(descriptor)
            }
        }
        return agents
    }

    public func detect(provider: AgentProvider) async throws -> AgentDescriptor? {
        let name = provider.rawValue
        guard let path = shellClient.resolveExecutable(named: name) else {
            return nil
        }

        let versionResult = try await shellClient.run(executable: path, arguments: ["--version"])
        let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return AgentDescriptor(provider: provider, path: path.path, version: version)
    }

    public func run(provider: AgentProvider, prompt: String) async throws -> String {
        try await runDetailed(provider: provider, prompt: prompt).output
    }

    public func runDetailed(
        provider: AgentProvider,
        prompt: String,
        eventHandler: (@Sendable (AgentRunEvent) async -> Void)? = nil
    ) async throws -> AgentRunResult {
        let arguments: [String]
        switch provider {
        case .claude:
            arguments = ["-p", prompt]
        case .codex:
            arguments = ["exec", "--skip-git-repo-check", prompt]
        }

        guard let executable = shellClient.resolveExecutable(named: provider.rawValue) else {
            throw AgentServiceError.executableNotFound(provider.rawValue)
        }

        if let eventHandler {
            await eventHandler(.started(executablePath: executable.path, arguments: arguments, isSharedLog: false))
        }

        let result = try await shellClient.runStreaming(executable: executable, arguments: arguments, timeout: executionTimeout) { event in
            guard let eventHandler else {
                return
            }
            switch event {
            case .started:
                break
            case .stdout(let text):
                await eventHandler(.stdout(text))
            case .stderr(let text):
                await eventHandler(.stderr(text))
            case .finished(let status):
                await eventHandler(.finished(exitCode: status))
            }
        }
        if result.status == SIGTERM {
            if let eventHandler {
                await eventHandler(.failed(message: AgentServiceError.executionTimedOut(executionTimeout).localizedDescription))
            }
            throw AgentServiceError.executionTimedOut(executionTimeout)
        }
        guard result.status == 0 else {
            if let eventHandler {
                await eventHandler(.failed(message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            throw AgentServiceError.executionFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw AgentServiceError.emptyOutput
        }
        return AgentRunResult(output: output, executablePath: executable.path, arguments: arguments, exitCode: result.status, stderr: result.stderr)
    }
}
