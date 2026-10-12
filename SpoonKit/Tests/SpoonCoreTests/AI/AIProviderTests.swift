import Foundation
import Testing

@testable import SpoonCore

@Suite("AI provider argv")
struct AIProviderArgvTests {
  private func makeLocator(_ runner: FakeCommandRunner) -> ToolLocator {
    // git exists everywhere; claude/codex resolve via override for the test.
    ToolLocator(runner: runner) { tool in
      switch tool {
      case .claude: "/usr/bin/true"
      case .codex: "/usr/bin/true"
      default: nil
      }
    }
  }

  @Test func claudeGenerateUsesHermeticHeadlessFlags() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-p",
        "--output-format", "text",
        "--max-turns", "1",
        "--permission-mode", "dontAsk",
        "--setting-sources", "user",
        "--strict-mcp-config",
        "--no-session-persistence",
      ],
      stdout: "feat: add feature\n"
    )
    let provider = ClaudeCodeProvider(runner: runner, toolLocator: makeLocator(runner))
    let message = try await provider.generateCommitMessage(prompt: "PROMPT")
    #expect(message == "feat: add feature")

    let command = try #require(runner.invocations.first)
    #expect(command.standardInput == Data("PROMPT".utf8))
  }

  @Test func codexGenerateUsesReadOnlySandbox() async throws {
    let runner = FakeCommandRunner()
    let provider = CodexProvider(runner: runner, toolLocator: makeLocator(runner))
    // No stub matches (argv contains a random temp path) — assert on the
    // recorded invocation after the expected failure instead.
    _ = try? await provider.generateCommitMessage(prompt: "PROMPT")
    let command = try #require(runner.invocations.first)
    #expect(
      command.arguments.starts(
        with: ["exec", "-", "--sandbox", "read-only", "--ephemeral", "--ignore-user-config", "-o"]
      )
    )
    #expect(command.arguments.contains("--skip-git-repo-check"))
    #expect(command.standardInput == Data("PROMPT".utf8))
  }

  @Test func missingCLIThrowsNotInstalled() async {
    let runner = FakeCommandRunner()
    // An override pointing at a non-executable path simulates "not
    // installed" even on machines that have the real CLI.
    let locator = ToolLocator(runner: runner) { _ in "/nonexistent/claude" }
    let provider = ClaudeCodeProvider(runner: runner, toolLocator: locator)
    await #expect(throws: AIError.self) {
      _ = try await provider.generateCommitMessage(prompt: "P")
    }
  }
}

@Suite("PromptBuilder")
struct PromptBuilderTests {
  @Test func commitPromptContainsContext() {
    let prompt = PromptBuilder.commitMessagePrompt(
      .init(
        branchName: "feature/x",
        recentSubjects: ["feat: a", "fix: b"],
        stagedDiff: "diff --git a/x b/x"
      )
    )
    #expect(prompt.contains("<branch>feature/x</branch>"))
    #expect(prompt.contains("feat: a\nfix: b"))
    #expect(prompt.contains("diff --git a/x b/x"))
  }

  @Test func oversizedDiffIsTruncated() {
    let huge = String(repeating: "x", count: 100_000)
    let prompt = PromptBuilder.commitMessagePrompt(
      .init(branchName: nil, recentSubjects: [], stagedDiff: huge)
    )
    #expect(prompt.count < 70_000)
    #expect(prompt.contains("diff truncated"))
  }
}
