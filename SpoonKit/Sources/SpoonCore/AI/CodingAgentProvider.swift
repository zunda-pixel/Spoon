import Foundation

/// A headless coding agent (Claude Code, Codex) driven through its CLI.
/// v1 surface is buffered request/response; streaming can layer on later
/// without changing callers.
public protocol CodingAgentProvider: Sendable {
  var id: AIProviderID { get }

  /// The CLI is installed and resolvable.
  func isAvailable() async -> Bool

  /// Pure generation from an injected prompt — no repository tool access.
  func generateCommitMessage(prompt: String) async throws -> String
}

/// Shared plumbing for CLI-backed providers.
enum AgentCLI {
  static func requireSuccess(_ result: CommandResult, provider: AIProviderID) throws {
    guard result.isSuccess else {
      throw AIError(
        kind: .cliFailed(
          exitCode: result.exitCode,
          stderrExcerpt: CommandError.excerpt(from: result.standardError)
        ),
        rawOutput: result.standardOutputText
      )
    }
  }
}
