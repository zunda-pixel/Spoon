public import Foundation

/// Claude Code via `claude -p` (headless). Prompts always go through stdin —
/// never argv (ARG_MAX, quoting, and `ps` leakage).
public struct ClaudeCodeProvider: CodingAgentProvider {
  public let id = AIProviderID.claudeCode

  private let runner: any CommandRunning
  private let toolLocator: ToolLocator

  public init(runner: any CommandRunning, toolLocator: ToolLocator) {
    self.runner = runner
    self.toolLocator = toolLocator
  }

  public func isAvailable() async -> Bool {
    await toolLocator.resolve(.claude) != nil
  }

  public func generateCommitMessage(prompt: String) async throws -> String {
    guard let claude = await toolLocator.resolve(.claude) else {
      throw AIError(kind: .notInstalled(id))
    }
    // Hermetic pure generation: user settings only, no repo hooks or MCP
    // servers, no tools, one turn, and no `/resume` list pollution.
    let command = Command(
      executable: claude,
      arguments: [
        "-p",
        "--output-format", "text",
        "--max-turns", "1",
        "--permission-mode", "dontAsk",
        "--setting-sources", "user",
        "--strict-mcp-config",
        "--no-session-persistence",
      ],
      standardInput: Data(prompt.utf8),
      timeout: .seconds(120)
    )
    let result = try await runner.run(command)
    try AgentCLI.requireSuccess(result, provider: id)
    let message = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else {
      throw AIError(kind: .outputUnparseable, rawOutput: result.standardOutputText)
    }
    return message
  }

  public func review(prompt: String, repository: URL) async throws -> ReviewReport {
    guard let claude = await toolLocator.resolve(.claude) else {
      throw AIError(kind: .notInstalled(id))
    }
    // Read-only agentic run: repository exploration allowed through an
    // explicit read-only tool allowlist; everything else is denied without
    // prompting (dontAsk). Repo-supplied hooks/MCP config never load.
    let command = Command(
      executable: claude,
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
      workingDirectory: repository,
      standardInput: Data(prompt.utf8),
      timeout: .seconds(600)
    )
    let result = try await runner.run(command)
    try AgentCLI.requireSuccess(result, provider: id)

    // `--output-format json` wraps the answer in an envelope whose
    // `result` field holds the (schema-constrained) JSON as a string.
    let raw = result.standardOutputText
    if let data = raw.data(using: .utf8),
      let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let inner = envelope["result"] as? String
    {
      return try AgentCLI.decodeReport(from: inner)
    }
    return try AgentCLI.decodeReport(from: raw)
  }
}
