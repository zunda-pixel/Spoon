public import Foundation

extension SystemGitClient {
  /// Compatibility wrapper for repository discovery.
  public static func repositoryRoot(
    containing url: URL,
    git: URL,
    runner: any CommandRunning
  ) async -> URL? {
    await GitRepositoryLifecycle.repositoryRoot(containing: url, git: git, runner: runner)
  }

  /// Compatibility wrapper for repository initialization.
  public static func initialize(
    at destination: URL,
    initialBranch: String,
    git: URL,
    runner: any CommandRunning
  ) async throws {
    try await GitRepositoryLifecycle.initialize(
      at: destination,
      initialBranch: initialBranch,
      git: git,
      runner: runner
    )
  }

  /// Compatibility wrapper for repository cloning.
  public static func clone(
    from remoteURL: String,
    to destination: URL,
    options: CloneOptions = .standard,
    git: URL,
    runner: any CommandRunning,
    progress: @escaping @Sendable (String) -> Void
  ) async throws {
    try await GitRepositoryLifecycle.clone(
      from: remoteURL,
      to: destination,
      options: options,
      git: git,
      runner: runner,
      progress: progress
    )
  }
}
