import Foundation
import Testing
@testable import FigBridgeCore

struct AgentIntegrationTests {
    @Test func agentServiceInvokesClaudeWithPromptArgument() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let scriptPath = sandbox.root.appendingPathComponent("claude")
        let logPath = sandbox.root.appendingPathComponent("claude.log")
        try makeExecutable(
            at: scriptPath,
            body: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "claude test"
              exit 0
            fi
            if [ "$1" = "-p" ]; then
              printf "%s" "$2" > "\(logPath.path)"
              echo "kind: yaml"
              exit 0
            fi
            exit 1
            """
        )

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: ["PATH": sandbox.root.path])
        let service = AgentService(shellClient: shell)

        let output = try await service.run(provider: .claude, prompt: "hello from claude")

        #expect(output == "kind: yaml")
        let loggedPrompt = try String(contentsOf: logPath, encoding: .utf8)
        #expect(loggedPrompt == "hello from claude")
    }

    @Test func agentServiceInvokesCodexWithExecArgument() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let scriptPath = sandbox.root.appendingPathComponent("codex")
        let logPath = sandbox.root.appendingPathComponent("codex.log")
        try makeExecutable(
            at: scriptPath,
            body: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "codex test"
              exit 0
            fi
            if [ "$1" = "exec" ]; then
              printf "%s" "$2" > "\(logPath.path)"
              echo "kind: yaml"
              exit 0
            fi
            exit 1
            """
        )

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: ["PATH": sandbox.root.path])
        let service = AgentService(shellClient: shell)

        let output = try await service.run(provider: .codex, prompt: "hello from codex")

        #expect(output == "kind: yaml")
        let loggedPrompt = try String(contentsOf: logPath, encoding: .utf8)
        #expect(loggedPrompt == "hello from codex")
    }
}
