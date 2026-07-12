import Foundation

/// Builds `Command` values for git invocations with the fixed flags and
/// environment every call must carry.
enum GitCommand {
  /// Applied to every invocation:
  /// - `GIT_TERMINAL_PROMPT=0`: never hang waiting for credentials
  /// - `GIT_OPTIONAL_LOCKS=0`: background reads must not take the index lock
  /// - `LC_ALL=C`: stable, parseable error messages
  static let environment: [String: String] = [
    "GIT_TERMINAL_PROMPT": "0",
    "GIT_OPTIONAL_LOCKS": "0",
    "LC_ALL": "C",
  ]

  static let baseArguments: [String] = [
    "-c", "color.ui=false",
    "-c", "core.quotePath=false",
  ]

  static func make(
    git: URL,
    repository: URL?,
    arguments: [String],
    extraEnvironment: [String: String] = [:],
    timeout: Duration? = .seconds(30)
  ) -> Command {
    Command(
      executable: git,
      arguments: baseArguments + arguments,
      workingDirectory: repository,
      environment: environment.merging(extraEnvironment) { _, override in override },
      timeout: timeout
    )
  }
}
