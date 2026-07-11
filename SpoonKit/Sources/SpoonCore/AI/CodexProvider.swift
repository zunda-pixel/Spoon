public import Foundation

/// OpenAI Codex via `codex exec`. The final agent message is read from the
/// `-o` artifact file — the most stable surface of the CLI — while stderr
/// progress is drained and discarded by the subprocess layer.
public struct CodexProvider: CodingAgentProvider {
  public let id = AIProviderID.codex

  private let runner: any CommandRunning
  private let toolLocator: ToolLocator

  public init(runner: any CommandRunning, toolLocator: ToolLocator) {
    self.runner = runner
    self.toolLocator = toolLocator
  }

  public func isAvailable() async -> Bool {
    await toolLocator.resolve(.codex) != nil
  }

  public func generateCommitMessage(prompt: String) async throws -> String {
    let output = try await run(
      prompt: prompt,
      extraArguments: ["--skip-git-repo-check"],
      workingDirectory: nil,
      timeout: .seconds(120)
    )
    let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else {
      throw AIError(kind: .outputUnparseable, rawOutput: output)
    }
    return message
  }

  public func review(prompt: String, repository: URL) async throws -> ReviewReport {
    let schemaFile = temporaryFile(suffix: "schema.json")
    try Data(PromptBuilder.reviewSchema.utf8).write(to: schemaFile)
    defer { try? FileManager.default.removeItem(at: schemaFile) }

    let output = try await run(
      prompt: prompt,
      extraArguments: [
        "--cd", repository.path(percentEncoded: false),
        "--output-schema", schemaFile.path(percentEncoded: false),
      ],
      workingDirectory: repository,
      timeout: .seconds(600)
    )
    return try AgentCLI.decodeReport(from: output)
  }

  // MARK: - Helpers

  private func run(
    prompt: String,
    extraArguments: [String],
    workingDirectory: URL?,
    timeout: Duration
  ) async throws -> String {
    guard let codex = await toolLocator.resolve(.codex) else {
      throw AIError(kind: .notInstalled(id))
    }
    let outputFile = temporaryFile(suffix: "codex-out.txt")
    defer { try? FileManager.default.removeItem(at: outputFile) }

    // `exec -` reads the prompt from stdin; read-only sandbox is
    // OS-enforced; --ephemeral keeps the user's session list clean.
    // --ignore-user-config: hermetic by default — a user config pinning an
    // unavailable model or a dead MCP server must not break Spoon tasks.
    let command = Command(
      executable: codex,
      arguments: [
        "exec", "-",
        "--sandbox", "read-only",
        "--ephemeral",
        "--ignore-user-config",
        "-o", outputFile.path(percentEncoded: false),
      ] + extraArguments,
      workingDirectory: workingDirectory,
      standardInput: Data(prompt.utf8),
      timeout: timeout
    )
    let result = try await runner.run(command)
    try AgentCLI.requireSuccess(result, provider: id)

    if let data = try? Data(contentsOf: outputFile), !data.isEmpty {
      return String(decoding: data, as: UTF8.self)
    }
    // Fallback: codex also prints the final message to stdout.
    return result.standardOutputText
  }

  private func temporaryFile(suffix: String) -> URL {
    URL.temporaryDirectory.appending(path: "spoon-\(UUID().uuidString)-\(suffix)")
  }
}
