import Foundation
import Testing
@testable import FigBridgeCore

struct AgentServiceTests {
    @Test func detectsAvailableAgentsAndReadsVersion() async throws {
        let fileManager = FileManager.default
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        let codexPath = sandbox.root.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nelse\n  echo \"$2\"\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 2.0.0\"\nelse\n  echo \"$2\"\nfi\n")
        #expect(fileManager.fileExists(atPath: claudePath.path))

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell)

        let agents = try await service.detectAvailableAgents()

        #expect(agents.count == 2)
        #expect(agents.first(where: { $0.provider == .claude })?.version == "claude 1.0.0")
        #expect(agents.first(where: { $0.provider == .codex })?.version == "codex 2.0.0")
    }

    @Test func returnsEmptyWhenNoAgentExists() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell)

        let agents = try await service.detectAvailableAgents()

        #expect(agents.isEmpty)
    }

    @Test func runsClaudeAndCodexWithExpectedArguments() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        let codexPath = sandbox.root.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nelif [ \"$1\" = \"-p\" ]; then\n  echo \"$2\"\nelse\n  exit 1\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 2.0.0\"\nelif [ \"$1\" = \"exec\" ]; then\n  echo \"$2\"\nelse\n  exit 1\nfi\n")

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell)

        let claudeOutput = try await service.run(provider: .claude, prompt: "hello")
        let codexOutput = try await service.run(provider: .codex, prompt: "world")

        #expect(claudeOutput == "hello")
        #expect(codexOutput == "world")
    }
}

private func makeExecutable(at url: URL, body: String) throws {
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
