public import Observation
import Defaults

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
  public internal(set) var submodules: [Submodule] = []
  /// Optional features of the installed git, used to hide unsupported actions.
  public internal(set) var gitCapabilities = GitCapabilities()
  /// Promisor remote of a partial clone; `nil` for a full clone.
  public internal(set) var partialCloneRemote: String?
  /// An in-progress rebase / cherry-pick / revert (conflict or edit pause).
  public internal(set) var sequencerState: SequencerState?
  /// An in-progress `git bisect`.
  public internal(set) var bisectState: BisectState?
  /// The first bad commit of the last bisect, until dismissed.
  public internal(set) var bisectResult: ObjectID?
  public internal(set) var isRefreshing = false
  /// A long-running mutation (fetch/pull/push/commit/…) is in flight.
  public internal(set) var isBusy = false
  public internal(set) var lastErrorMessage: String?
  /// Hide whitespace-only changes in diffs, app-wide.
  public var diffIgnoresWhitespace = Defaults[.diffIgnoresWhitespace] {
    didSet { Defaults[.diffIgnoresWhitespace] = diffIgnoresWhitespace }
  }
  /// Highlight changed words within modified diff lines, app-wide.
  public var diffHighlightsWordChanges = Defaults[.diffHighlightsWordChanges] {
    didSet { Defaults[.diffHighlightsWordChanges] = diffHighlightsWordChanges }
  }
  /// Stash local changes around every pull (`--autostash`), app-wide.
  public var pullAutostash = Defaults[.pullAutostash] {
    didSet { Defaults[.pullAutostash] = pullAutostash }
  }
  /// Add a `Signed-off-by:` trailer to commits, remembered per repository.
  public var commitSignsOff = false {
    didSet {
      var ids = Set(Defaults[.commitSignOffRepositoryIDs])
      if commitSignsOff { ids.insert(repository.id) } else { ids.remove(repository.id) }
      Defaults[.commitSignOffRepositoryIDs] = ids.sorted()
    }
  }
  /// Bumped after Spoon writes `git config`, so views that read it reload.
  public internal(set) var configGeneration = 0
  public internal(set) var focusedHistoryReferenceIDs: Set<String> = []
  public internal(set) var hiddenHistoryReferenceIDs: Set<String> = []
  /// Whether `lastErrorMessage` came from a background read (git refresh or
  /// history load). Background errors clear automatically once the read
  /// recovers; mutation errors stay until the user dismisses them.
  var lastErrorIsFromBackgroundRead = false

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
    self.focusedHistoryReferenceIDs = Set(
      Defaults[.historyFocusedReferenceIDs][repository.id] ?? []
    )
    self.hiddenHistoryReferenceIDs = Set(
      Defaults[.historyHiddenReferenceIDs][repository.id] ?? []
    )
    self.commitSignsOff = Defaults[.commitSignOffRepositoryIDs].contains(repository.id)
  }

  isolated deinit {
    watchTask?.cancel()
    gitRefreshTask?.cancel()
  }

  public func clearError() {
    lastErrorMessage = nil
    lastErrorIsFromBackgroundRead = false
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
