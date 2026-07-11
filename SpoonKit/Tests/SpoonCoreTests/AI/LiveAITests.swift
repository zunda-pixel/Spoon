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
  @Test(.timeLimit(.minutes(10)))
  func claudeReviewsSeededBug() async throws {
    let git = URL(filePath: "/usr/bin/git")
    let root = URL.temporaryDirectory.appending(path: "spoon-live-review-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    func runGit(_ arguments: [String]) async throws {
      let command = Command(executable: git, arguments: arguments, workingDirectory: root)
      _ = try await runner.run(command).checkSuccess(of: command)
    }

    try await runGit(["init", "-q", "--initial-branch=main"])
    try await runGit(["config", "user.email", "t@e.com"])
    try await runGit(["config", "user.name", "T"])
    try Data(
      """
      func loadName(from dictionary: [String: String]) -> String {
        return dictionary["name"] ?? "unknown"
      }
      """.utf8
    ).write(to: root.appending(path: "Names.swift"))
    try await runGit(["add", "."])
    try await runGit(["commit", "-qm", "add safe name loading"])
    try await runGit(["switch", "-qc", "feature/risky"])
    try Data(
      """
      func loadName(from dictionary: [String: String]) -> String {
        // Force-unwraps a missing key and crashes on absent names.
        return dictionary["name"]!
      }
      """.utf8
    ).write(to: root.appending(path: "Names.swift"))
    try await runGit(["commit", "-aqm", "simplify name loading"])

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let base = try await client.mergeBase("main", "HEAD")
    let diff = try await client.diffText(from: base.rawValue, to: "HEAD")
    let context = PromptBuilder.ReviewContext(
      branchName: "feature/risky",
      baseReference: "main (merge-base \(base.shortened))",
      diff: diff,
      guidelines: nil
    )

    let provider = ClaudeCodeProvider(runner: runner, toolLocator: ToolLocator(runner: runner))
    let report = try await provider.review(
      prompt: PromptBuilder.reviewPrompt(context),
      repository: root
    )
    print("=== review summary ===\n\(report.summary)\n=== findings: \(report.findings.count)")
    for finding in report.findings {
      print("- [\(finding.severity.rawValue)] \(finding.file): \(finding.title)")
    }
    // The seeded force-unwrap must be caught.
    #expect(!report.findings.isEmpty)
    #expect(report.findings.contains { $0.file.contains("Names.swift") })
  }
}
