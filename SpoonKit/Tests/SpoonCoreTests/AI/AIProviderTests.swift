import Foundation
import Testing

@testable import SpoonCore

@Suite("AI JSON extraction")
struct AIJSONExtractionTests {
  private let validReport = """
    {"summary": "Looks good", "findings": [
      {"file": "a.swift", "line": 12, "anchorSnippet": "let x = 1",
       "severity": "high", "title": "Bug", "body": "Details", "suggestion": "let x = 2"}
    ]}
    """

  @Test func decodesPlainJSON() throws {
    let report = try AgentCLI.decodeReport(from: validReport)
    #expect(report.summary == "Looks good")
    #expect(report.findings.count == 1)
    #expect(report.findings[0].severity == .high)
    #expect(report.findings[0].anchorSnippet == "let x = 1")
  }

  @Test func decodesFencedJSON() throws {
    let report = try AgentCLI.decodeReport(from: "Here you go:\n```json\n\(validReport)\n```\nDone.")
    #expect(report.findings.count == 1)
  }

  @Test func decodesProseWrappedJSON() throws {
    let report = try AgentCLI.decodeReport(from: "The review result is \(validReport) — hope that helps!")
    #expect(report.summary == "Looks good")
  }

  @Test func unknownSeverityBecomesMedium() throws {
    let report = try AgentCLI.decodeReport(
      from: #"{"summary": "s", "findings": [{"file": "a", "severity": "CATASTROPHIC", "title": "t", "body": "b"}]}"#
    )
    #expect(report.findings[0].severity == .medium)
  }

  @Test func emptyFindingsIsValid() throws {
    let report = try AgentCLI.decodeReport(from: #"{"summary": "All clear", "findings": []}"#)
    #expect(report.findings.isEmpty)
  }

  @Test func garbageThrowsWithRawPreserved() {
    do {
      _ = try AgentCLI.decodeReport(from: "I could not produce JSON, sorry.")
      Issue.record("expected throw")
    } catch let error as AIError {
      #expect(error.rawOutput?.contains("sorry") == true)
    } catch {
      Issue.record("unexpected error type")
    }
  }
}

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

  @Test func claudeReviewRestrictsToolsAndUsesSchema() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-p",
        "--output-format", "json",
        "--json-schema", PromptBuilder.reviewSchema,
        "--allowedTools", "Read", "Grep", "Glob",
        "--disallowedTools", "Bash", "Write", "Edit", "NotebookEdit", "WebFetch", "WebSearch",
        "--permission-mode", "dontAsk",
        "--setting-sources", "user",
        "--strict-mcp-config",
        "--no-session-persistence",
      ],
      stdout: #"{"result": "{\"summary\": \"ok\", \"findings\": []}"}"#
    )
    let provider = ClaudeCodeProvider(runner: runner, toolLocator: makeLocator(runner))
    let report = try await provider.review(prompt: "P", repository: URL(filePath: "/tmp/x"))
    #expect(report.summary == "ok")

    let command = try #require(runner.invocations.first)
    #expect(command.workingDirectory == URL(filePath: "/tmp/x"))
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
