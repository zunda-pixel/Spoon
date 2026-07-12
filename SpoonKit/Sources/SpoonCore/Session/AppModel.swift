public import Foundation
public import Observation

import Defaults

/// App-wide state: recent repositories, shared process infrastructure, and
/// the factory for per-window `RepositoryModel`s.
@MainActor
@Observable
public final class AppModel {
  /// The app's single instance, for App Intents (which run outside the
  /// SwiftUI environment but on the main actor).
  public private(set) static weak var shared: AppModel?

  public private(set) var recentRepositories: [Repository]

  /// Folder handed to the app from outside (`open -a Spoon <dir>`, Finder).
  /// Consumed exactly once by whichever window reacts first.
  public private(set) var externalOpenRequest: URL?

  public func submitExternalOpenRequest(_ url: URL) {
    externalOpenRequest = url
  }

  public func takeExternalOpenRequest() -> URL? {
    defer { externalOpenRequest = nil }
    return externalOpenRequest
  }

  public let toolLocator: ToolLocator
  private let runner: any CommandRunning
  private static let maxRecents = 20

  public init(runner: any CommandRunning = SubprocessCommandRunner()) {
    self.runner = runner
    defer { Self.shared = self }
    self.toolLocator = ToolLocator(
      runner: runner,
      override: { tool in Defaults[.toolPathOverrides][tool.rawValue] }
    )
    self.recentRepositories = Defaults[.recentRepositoryPaths].map {
      Repository(rootURL: URL(filePath: $0, directoryHint: .isDirectory))
    }
  }

  public enum OpenError: LocalizedError {
    case gitNotFound
    case notARepository(URL)

    public var errorDescription: String? {
      switch self {
      case .gitNotFound:
        "Could not find git. Install the Xcode Command Line Tools, or set a path in Settings."
      case .notARepository(let url):
        "\(url.path(percentEncoded: false)) is not inside a git repository."
      }
    }
  }

  /// Clones `remoteURL` into `destination` and records it in recents.
  /// `progress` receives git's latest `--progress` line off the main actor.
  public func cloneRepository(
    from remoteURL: String,
    to destination: URL,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Repository {
    let git = try await resolveGit()
    try await SystemGitClient.clone(
      from: remoteURL, to: destination, git: git, runner: runner, progress: progress)
    return try await openRepository(at: destination)
  }

  /// Resolves `url` to its repository root and records it in recents.
  public func openRepository(at url: URL) async throws -> Repository {
    let git = try await resolveGit()
    guard
      let root = await SystemGitClient.repositoryRoot(containing: url, git: git, runner: runner)
    else {
      throw OpenError.notARepository(url)
    }
    let repository = Repository(rootURL: root)
    addRecent(repository)
    return repository
  }

  public func makeRepositoryModel(for repository: Repository) async throws -> RepositoryModel {
    let git = try await resolveGit()
    let client = SystemGitClient(repositoryRoot: repository.rootURL, git: git, runner: runner)
    let tokenProvider = ChainedTokenProvider([
      GhCLITokenProvider(runner: runner, toolLocator: toolLocator),
      KeychainTokenProvider(),
    ])
    addRecent(repository)
    let model = RepositoryModel(
      repository: repository,
      gitClient: client,
      gitHub: GitHubAPIClient(tokenProvider: tokenProvider)
    )
    model.aiProviders = [
      .claudeCode: ClaudeCodeProvider(runner: runner, toolLocator: toolLocator),
      .codex: CodexProvider(runner: runner, toolLocator: toolLocator),
    ]
    return model
  }

  public func removeRecent(_ repository: Repository) {
    recentRepositories.removeAll { $0.id == repository.id }
    persistRecents()
  }

  // MARK: - Helpers

  private func resolveGit() async throws -> URL {
    guard let git = await toolLocator.resolve(.git) else { throw OpenError.gitNotFound }
    return git
  }

  private func addRecent(_ repository: Repository) {
    var updated = recentRepositories.filter { $0.id != repository.id }
    updated.insert(repository, at: 0)
    recentRepositories = Array(updated.prefix(Self.maxRecents))
    persistRecents()
  }

  private func persistRecents() {
    Defaults[.recentRepositoryPaths] = recentRepositories.map(\.id)
  }
}
