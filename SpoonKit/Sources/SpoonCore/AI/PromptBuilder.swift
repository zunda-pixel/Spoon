public import Foundation

/// Builds the prompts and JSON schemas for AI tasks. Pure — snapshot-testable.
public enum PromptBuilder {
  /// Keep prompts well under CLI context limits; diffs are the fat part.
  static let diffBudget = 60_000

  public struct CommitContext: Sendable {
    public var branchName: String?
    public var recentSubjects: [String]
    public var stagedDiff: String

    public init(branchName: String?, recentSubjects: [String], stagedDiff: String) {
      self.branchName = branchName
      self.recentSubjects = recentSubjects
      self.stagedDiff = stagedDiff
    }
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

  public struct ReviewContext: Sendable {
    public var branchName: String?
    public var baseReference: String
    public var diff: String
    public var guidelines: String?

    public init(branchName: String?, baseReference: String, diff: String, guidelines: String?) {
      self.branchName = branchName
      self.baseReference = baseReference
      self.diff = diff
      self.guidelines = guidelines
    }
  }

  public static func reviewPrompt(_ context: ReviewContext) -> String {
    var prompt = """
      You are reviewing the changes on branch \(context.branchName ?? "HEAD") \
      against \(context.baseReference).

      You MAY use your read-only tools to read surrounding code, callers, and
      tests to verify suspicions before reporting them.

      Review rules:
      - Report ONLY problems introduced or worsened by this diff. Ignore
        pre-existing issues.
      - Prioritize: correctness bugs, data races / concurrency violations,
        security issues, API misuse. Style only when it violates the project
        guidelines below.
      - For each finding include `anchorSnippet`: the exact verbatim source
        line the finding is about, copied from the diff.
      - `suggestion` must be drop-in replacement code, or omitted.
      - At most 20 findings, ordered by severity (blocker, high, medium, low, nit).
      - If the change is fine, return an empty findings array and say so in
        `summary` — do not manufacture findings.

      """
    if let guidelines = context.guidelines, !guidelines.isEmpty {
      prompt += "<project_guidelines>\n\(String(guidelines.prefix(8_000)))\n</project_guidelines>\n"
    }
    prompt += "<diff>\n\(budgeted(context.diff))\n</diff>\n"
    return prompt
  }

  /// JSON schema shared by both CLIs' structured-output flags.
  public static let reviewSchema = """
    {
      "type": "object",
      "properties": {
        "summary": { "type": "string" },
        "findings": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "file": { "type": "string" },
              "line": { "type": ["integer", "null"] },
              "anchorSnippet": { "type": ["string", "null"] },
              "severity": { "type": "string", "enum": ["blocker", "high", "medium", "low", "nit"] },
              "title": { "type": "string" },
              "body": { "type": "string" },
              "suggestion": { "type": ["string", "null"] }
            },
            "required": ["file", "severity", "title", "body"],
            "additionalProperties": true
          }
        }
      },
      "required": ["summary", "findings"],
      "additionalProperties": true
    }
    """

  static func budgeted(_ diff: String) -> String {
    guard diff.count > diffBudget else { return diff }
    return diff.prefix(diffBudget) + "\n…(diff truncated at \(diffBudget) characters)"
  }

  /// First guidelines file found in the repo, for review prompts.
  public static func guidelines(in root: URL) -> String? {
    for name in ["CLAUDE.md", "AGENTS.md", "CONTRIBUTING.md", ".spoon/review-guidelines.md"] {
      let url = root.appending(path: name)
      if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
        return content
      }
    }
    return nil
  }
}
