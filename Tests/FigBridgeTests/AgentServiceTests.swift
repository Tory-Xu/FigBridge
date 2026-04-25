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

    @Test func ignoresMissingCustomLookupDirectories() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let resolved = shell.resolveExecutable(named: "definitely-missing-agent")

        #expect(resolved == nil)
    }

    @Test func detectsAgentsFromFallbackHomeBinDirectories() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let homeDirectory = sandbox.root.appendingPathComponent("home", isDirectory: true)
        let fallbackDirectory = homeDirectory.appendingPathComponent(".superconductor/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)

        let claudePath = fallbackDirectory.appendingPathComponent("claude")
        let codexPath = fallbackDirectory.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 9.9.9\"\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 8.8.8\"\nfi\n")

        let shell = ShellClient(pathLookupDirectories: [], environment: ["HOME": homeDirectory.path, "PATH": "/usr/bin:/bin"])
        let service = AgentService(shellClient: shell)

        let agents = try await service.detectAvailableAgents()

        #expect(agents.count == 2)
        #expect(agents.first(where: { $0.provider == .claude })?.path == claudePath.path)
        #expect(agents.first(where: { $0.provider == .codex })?.path == codexPath.path)
    }

    @Test func runsClaudeAndCodexWithExpectedArguments() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let claudePath = sandbox.root.appendingPathComponent("claude")
        let codexPath = sandbox.root.appendingPathComponent("codex")
        try makeExecutable(at: claudePath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"claude 1.0.0\"\nelif [ \"$1\" = \"-p\" ]; then\n  echo \"$2\"\nelse\n  exit 1\nfi\n")
        try makeExecutable(at: codexPath, body: "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then\n  echo \"codex 2.0.0\"\nelif [ \"$1\" = \"exec\" ]; then\n  echo \"$3\"\nelse\n  exit 1\nfi\n")

        let shell = ShellClient(pathLookupDirectories: [sandbox.root], environment: [:])
        let service = AgentService(shellClient: shell)

        let claudeOutput = try await service.run(provider: .claude, prompt: "hello")
        let codexOutput = try await service.run(provider: .codex, prompt: "world")

        #expect(claudeOutput == "hello")
        #expect(codexOutput == "world")
    }

    @Test func runUsesExpandedPathForWrapperDependencies() async throws {
        let sandbox = try TestSandbox()
        defer { sandbox.cleanup() }

        let homeDirectory = sandbox.root.appendingPathComponent("home", isDirectory: true)
        let wrapperDirectory = homeDirectory.appendingPathComponent(".superconductor/bin", isDirectory: true)
        let nodeDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapperDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeDirectory, withIntermediateDirectories: true)

        let nodePath = nodeDirectory.appendingPathComponent("node")
        try makeExecutable(at: nodePath, body: "#!/bin/sh\necho \"fake node\"\n")

        let claudePath = wrapperDirectory.appendingPathComponent("claude")
        try makeExecutable(
            at: claudePath,
            body: """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "claude wrapper"
              exit 0
            fi
            env node >/dev/null 2>&1 || { echo "env: node: No such file or directory" >&2; exit 127; }
            echo "$2"
            """
        )

        let shell = ShellClient(
            pathLookupDirectories: [],
            environment: [
                "HOME": homeDirectory.path,
                "PATH": "/usr/bin:/bin"
            ]
        )
        let service = AgentService(shellClient: shell)

        let output = try await service.run(provider: .claude, prompt: "hello with node")

        #expect(output == "hello with node")
    }
}
