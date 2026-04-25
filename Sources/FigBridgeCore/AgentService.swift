import Foundation

public enum AgentServiceError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(String)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "未找到可执行 agent: \(name)"
        case .executionFailed(let message):
            message
        case .emptyOutput:
            "agent 输出为空"
        }
    }
}

public struct AgentRunResult: Sendable {
    public let output: String
    public let executablePath: String
    public let arguments: [String]

    public init(output: String, executablePath: String, arguments: [String]) {
        self.output = output
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct AgentService: Sendable {
    public let shellClient: ShellClient

    public init(shellClient: ShellClient = ShellClient()) {
        self.shellClient = shellClient
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

    public func runDetailed(provider: AgentProvider, prompt: String) async throws -> AgentRunResult {
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

        let result = try await shellClient.run(executable: executable, arguments: arguments)
        guard result.status == 0 else {
            throw AgentServiceError.executionFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw AgentServiceError.emptyOutput
        }
        return AgentRunResult(output: output, executablePath: executable.path, arguments: arguments)
    }
}
