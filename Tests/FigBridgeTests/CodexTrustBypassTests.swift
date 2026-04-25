import Foundation
import Testing
@testable import FigBridgeCore

struct CodexTrustBypassTests {
    @Test func codexUsesSkipGitRepoCheckFlag() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let scriptPath = sandbox.root.appendingPathComponent("codex")
        let logPath = sandbox.root.appendingPathComponent("codex-args.log")
        try makeExecutable(
            at: scriptPath,
            body: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "codex test"
              exit 0
            fi
            printf "%s" "$*" > "\(logPath.path)"
            echo "kind: yaml"
            """
        )

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: ["PATH": sandbox.root.path])
        let service = AgentService(shellClient: shell)

        _ = try await service.run(provider: .codex, prompt: "hello")

        let loggedArguments = try String(contentsOf: logPath, encoding: .utf8)
        #expect(loggedArguments.contains("exec"))
        #expect(loggedArguments.contains("--skip-git-repo-check"))
    }
}
