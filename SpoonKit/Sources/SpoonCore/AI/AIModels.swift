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

@MemberwiseInit(.public)
public struct AIError: Error, Sendable, LocalizedError {
  public enum Kind: Sendable, Equatable {
    case notInstalled(AIProviderID)
    case cliFailed(exitCode: Int32, stderrExcerpt: String)
    case outputUnparseable
    case noChanges
    case timedOut
  }

  public var kind: Kind
  /// Raw model output, kept so a failed parse is never a total loss.
  public var rawOutput: String? = nil

  public var errorDescription: String? {
    switch kind {
    case .notInstalled(let provider):
      "\(provider.displayName) CLI is not installed (or not signed in)."
    case .cliFailed(let code, let stderr):
      "The AI CLI exited with code \(code).\n\(stderr)"
    case .outputUnparseable:
      "Could not parse the AI's response."
    case .noChanges:
      "There are no changes to work with."
    case .timedOut:
      "The AI run timed out."
    }
  }
}
