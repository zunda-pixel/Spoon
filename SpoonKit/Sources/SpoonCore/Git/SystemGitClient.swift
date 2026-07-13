public import Foundation

/// `GitClient` backed by the system git CLI.
///
/// One actor per repository: git's index lock makes concurrent mutation
/// pointless, so serialization here is the boring correct choice.
public actor SystemGitClient: GitClient {
  public nonisolated let repositoryRoot: URL
  let git: URL
  let runner: any CommandRunning

  public init(repositoryRoot: URL, git: URL, runner: any CommandRunning) {
    self.repositoryRoot = repositoryRoot
    self.git = git
    self.runner = runner
  }

  // Shared command execution remains actor-isolated.
  // MARK: - Helpers

  func run(_ arguments: [String], timeout: Duration? = .seconds(30)) async throws -> CommandResult {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: arguments,
      timeout: timeout
    )
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
