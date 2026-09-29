public import Foundation

/// `GitClient` backed by the system git CLI.
///
/// One actor per repository: git's index lock makes concurrent mutation
/// pointless, so serialization here is the boring correct choice.
public actor SystemGitClient: GitClient {
  public nonisolated let repositoryRoot: URL
  let git: URL
  let runner: any CommandRunning
  /// The executable never changes for this actor, so one successful
  /// `git version` answers every later capability check.
  private var cachedCapabilities: GitCapabilities?

  public init(repositoryRoot: URL, git: URL, runner: any CommandRunning) {
    self.repositoryRoot = repositoryRoot
    self.git = git
    self.runner = runner
  }

  public func capabilities() async -> GitCapabilities {
    if let cachedCapabilities { return cachedCapabilities }
    guard
      let result = try? await run(["version"], timeout: .seconds(10)),
      let version = GitVersionParser.parse(result.standardOutputText)
    else {
      // Not cached: a transient launch failure should not hide features
      // for the lifetime of the window.
      return GitCapabilities()
    }
    let capabilities = GitCapabilities(version: version)
    cachedCapabilities = capabilities
    return capabilities
  }

  // Shared command execution remains actor-isolated.
  // MARK: - Helpers

  func run(
    _ arguments: [String],
    standardInput: Data? = nil,
    timeout: Duration? = .seconds(30)
  ) async throws -> CommandResult {
    var command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: arguments,
      timeout: timeout
    )
    command.standardInput = standardInput
    return try await runner.run(command).checkSuccess(of: command)
  }

  func runVoid(
    _ arguments: [String],
    standardInput: Data? = nil,
    extraEnvironment: [String: String] = [:],
    timeout: Duration? = .seconds(30)
  ) async throws {
    var command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: arguments,
      extraEnvironment: extraEnvironment,
      timeout: timeout
    )
    command.standardInput = standardInput
    _ = try await runner.run(command).checkSuccess(of: command)
  }

}
