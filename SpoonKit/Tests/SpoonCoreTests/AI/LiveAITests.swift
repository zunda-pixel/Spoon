import Foundation
import Testing

@testable import SpoonCore

/// Live runs against the real claude/codex CLIs (uses the user's login and
/// quota). Opt-in: SPOON_LIVE_AI=1 swift test --filter LiveAI
@Suite(
  "LiveAI",
  .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["SPOON_LIVE_AI"] == "1")
)
struct LiveAITests {
  private let runner = SubprocessCommandRunner()

  private var prompt: String {
    PromptBuilder.commitMessagePrompt(
      .init(
        branchName: "feature/greeting",
        recentSubjects: ["feat: add farewell message", "fix: trim whitespace in names"],
        stagedDiff: """
          diff --git a/greeting.swift b/greeting.swift
          --- a/greeting.swift
          +++ b/greeting.swift
          @@ -1,3 +1,3 @@
           func greet(name: String) -> String {
          -  "Hello, \\(name)"
          +  "Hello, \\(name)! Welcome back."
           }
          """
      )
    )
  }

  @Test(.timeLimit(.minutes(3)))
  func claudeGeneratesCommitMessage() async throws {
    let provider = ClaudeCodeProvider(runner: runner, toolLocator: ToolLocator(runner: runner))
    let message = try await provider.generateCommitMessage(prompt: prompt)
    print("=== claude message ===\n\(message)\n======")
    let subject = message.split(separator: "\n").first ?? ""
    #expect(!subject.isEmpty)
    #expect(subject.count <= 100)  // soft sanity, not the 72-char style rule
  }

  @Test(.timeLimit(.minutes(3)))
  func codexGeneratesCommitMessage() async throws {
    let provider = CodexProvider(runner: runner, toolLocator: ToolLocator(runner: runner))
    let message = try await provider.generateCommitMessage(prompt: prompt)
    print("=== codex message ===\n\(message)\n======")
    #expect(!message.isEmpty)
  }

  /// Full agentic review against a throwaway repo with a seeded
  /// force-unwrap bug. Slow (~1–3 min); exercises the read-only tool
  /// allowlist, schema output, and finding decode end-to-end.
}
