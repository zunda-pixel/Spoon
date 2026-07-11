public import Foundation
public import MemberwiseInit

public enum AIProviderID: String, Sendable, CaseIterable, Codable, Identifiable {
  case claudeCode
  case codex

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    }
  }

  public var tool: ExternalTool {
    switch self {
    case .claudeCode: .claude
    case .codex: .codex
    }
  }
}

/// Structured output of commit-message generation.
public struct CommitMessageProposal: Sendable, Hashable, Codable {
  public var subject: String
  public var body: String?
  public var alternativeSubjects: [String]?

  public var fullMessage: String {
    guard let body, !body.isEmpty else { return subject }
    return "\(subject)\n\n\(body)"
  }
}

/// One review finding. `anchorSnippet` is the robustness key: models are
/// unreliable about line numbers but reliable about quoting the line
/// verbatim, so we re-locate findings by snippet after decoding.
@MemberwiseInit(.public)
public struct ReviewFinding: Sendable, Hashable, Codable, Identifiable {
  public enum Severity: String, Sendable, Codable, CaseIterable {
    case blocker, high, medium, low, nit

    public var sortOrder: Int {
      switch self {
      case .blocker: 0
      case .high: 1
      case .medium: 2
      case .low: 3
      case .nit: 4
      }
    }
  }

  public var file: String
  public var line: Int? = nil
  public var anchorSnippet: String? = nil
  public var severity: Severity
  public var title: String
  public var body: String
  public var suggestion: String? = nil

  public var id: String { "\(file):\(line ?? 0):\(title)" }

  // Lenient decoding: unknown severity strings become .medium instead of
  // failing the whole report.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    file = try container.decode(String.self, forKey: .file)
    line = try? container.decodeIfPresent(Int.self, forKey: .line)
    anchorSnippet = try? container.decodeIfPresent(String.self, forKey: .anchorSnippet)
    let rawSeverity = (try? container.decode(String.self, forKey: .severity)) ?? ""
    severity = Severity(rawValue: rawSeverity.lowercased()) ?? .medium
    title = try container.decode(String.self, forKey: .title)
    body = (try? container.decode(String.self, forKey: .body)) ?? ""
    suggestion = try? container.decodeIfPresent(String.self, forKey: .suggestion)
  }
}

public struct ReviewReport: Sendable, Hashable, Codable {
  public var summary: String
  public var findings: [ReviewFinding]

  public init(summary: String, findings: [ReviewFinding]) {
    self.summary = summary
    self.findings = findings
  }
}

public struct AIError: Error, Sendable, LocalizedError {
  public enum Kind: Sendable, Equatable {
    case notInstalled(AIProviderID)
    case cliFailed(exitCode: Int32, stderrExcerpt: String)
    case outputUnparseable
    case nothingToReview
    case timedOut
  }

  public var kind: Kind
  /// Raw model output, kept so a failed parse is never a total loss.
  public var rawOutput: String?

  public init(kind: Kind, rawOutput: String? = nil) {
    self.kind = kind
    self.rawOutput = rawOutput
  }

  public var errorDescription: String? {
    switch kind {
    case .notInstalled(let provider):
      "\(provider.displayName) CLI is not installed (or not signed in)."
    case .cliFailed(let code, let stderr):
      "The AI CLI exited with code \(code).\n\(stderr)"
    case .outputUnparseable:
      "Could not parse the AI's response."
    case .nothingToReview:
      "There are no changes to work with."
    case .timedOut:
      "The AI run timed out."
    }
  }
}
