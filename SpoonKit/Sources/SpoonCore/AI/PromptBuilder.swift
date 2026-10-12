import Foundation
public import MemberwiseInit

/// Builds the prompts and JSON schemas for AI tasks. Pure — snapshot-testable.
public enum PromptBuilder {
  /// Keep prompts well under CLI context limits; diffs are the fat part.
  static let diffBudget = 60_000

  @MemberwiseInit(.public)
  public struct CommitContext: Sendable {
    public var branchName: String?
    public var recentSubjects: [String]
    public var stagedDiff: String
  }

  public static func commitMessagePrompt(_ context: CommitContext) -> String {
    var prompt = """
      You write git commit messages. Reply with ONLY the commit message — no
      preamble, no code fences, no commentary.

      Rules:
      - Subject line ≤ 72 characters, imperative mood.
      - Mimic the style visible in <recent_commits> (language, prefixes, tense).
      - Add a short body (blank line after subject) only when the WHY isn't
        obvious from the diff; omit it for trivial changes.
      - Never invent issue numbers.

      """
    if let branch = context.branchName {
      prompt += "<branch>\(branch)</branch>\n"
    }
    if !context.recentSubjects.isEmpty {
      prompt += "<recent_commits>\n"
      prompt += context.recentSubjects.prefix(10).joined(separator: "\n")
      prompt += "\n</recent_commits>\n"
    }
    prompt += "<staged_changes>\n\(budgeted(context.stagedDiff))\n</staged_changes>\n"
    return prompt
  }

  static func budgeted(_ diff: String) -> String {
    guard diff.count > diffBudget else { return diff }
    return diff.prefix(diffBudget) + "\n…(diff truncated at \(diffBudget) characters)"
  }
}
