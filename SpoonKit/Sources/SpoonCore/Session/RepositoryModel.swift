public import Observation

/// Per-window facade tying one repository's git state and feature stores to the UI.
@MainActor
@Observable
public final class RepositoryModel {
  public let repository: Repository

  public internal(set) var status: WorkingTreeStatus?
  /// Directory trees for the Changes list, rebuilt alongside `status`.
  public internal(set) var changeTrees = ChangeTrees.empty
  public internal(set) var branches: [Branch] = []
  public internal(set) var remotes: [Remote] = []
  public internal(set) var remoteBranchesByRemote: [String: [Branch]] = [:]
  public internal(set) var stashes: [Stash] = []
  public internal(set) var tags: [Tag] = []
  public internal(set) var worktrees: [Worktree] = []
  public internal(set) var supportsBackfill = false
  /// An in-progress rebase / cherry-pick / revert (conflict or edit pause).
  public internal(set) var sequencerState: SequencerState?
  public internal(set) var isRefreshing = false
  /// A long-running mutation (fetch/pull/push/commit/…) is in flight.
  public internal(set) var isBusy = false
  public internal(set) var lastErrorMessage: String?

  let gitClient: any GitClient
  let historyStore: HistoryStore
  let pullRequestStore: PullRequestStore
  let aiStore: AIStore
  var watchTask: Task<Void, Never>?
  var gitRefreshTask: Task<Void, Never>?

  public init(repository: Repository, gitClient: any GitClient, gitHub: GitHubAPIClient? = nil) {
    self.repository = repository
    self.gitClient = gitClient
    self.historyStore = HistoryStore(gitClient: gitClient)
    self.pullRequestStore = PullRequestStore(
      repositoryID: repository.id,
      gitHub: gitHub
    )
    self.aiStore = AIStore(
      repositoryURL: repository.rootURL,
      gitClient: gitClient
    )
  }

  isolated deinit {
    watchTask?.cancel()
    gitRefreshTask?.cancel()
  }

  public func clearError() {
    lastErrorMessage = nil
  }

  public var currentBranch: Branch? {
    branches.first(where: \.isCurrent)
  }

  /// Count badge for the Changes sidebar row.
  public var pendingChangeCount: Int {
    guard let status else { return 0 }
    return status.entries.count { !$0.isIgnored }
  }
}
