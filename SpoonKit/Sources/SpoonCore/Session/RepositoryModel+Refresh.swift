import Foundation

/// A complete, internally consistent result of the repository's independent git reads.
public struct RepositoryGitSnapshot: Sendable, Hashable {
  public var status: WorkingTreeStatus
  public var branches: [Branch]
  public var remotes: [Remote]
  public var remoteBranchesByRemote: [String: [Branch]]
  public var stashes: [Stash]
  public var tags: [Tag]
  public var worktrees: [Worktree]
  public var submodules: [Submodule]
  public var sequencerState: SequencerState?
  public var bisectState: BisectState?
  public var capabilities: GitCapabilities
  /// Promisor remote of a partial clone; `nil` for a full clone.
  public var partialCloneRemote: String?
  /// A shallow clone, missing history beyond a boundary.
  public var isShallow: Bool

  public init(
    status: WorkingTreeStatus,
    branches: [Branch],
    remotes: [Remote],
    remoteBranchesByRemote: [String: [Branch]],
    stashes: [Stash],
    tags: [Tag],
    worktrees: [Worktree],
    submodules: [Submodule] = [],
    sequencerState: SequencerState?,
    bisectState: BisectState? = nil,
    capabilities: GitCapabilities,
    partialCloneRemote: String? = nil,
    isShallow: Bool = false
  ) {
    self.status = status
    self.branches = branches
    self.remotes = remotes
    self.remoteBranchesByRemote = remoteBranchesByRemote
    self.stashes = stashes
    self.tags = tags
    self.worktrees = worktrees
    self.submodules = submodules
    self.sequencerState = sequencerState
    self.bisectState = bisectState
    self.capabilities = capabilities
    self.partialCloneRemote = partialCloneRemote
    self.isShallow = isShallow
  }

  static func load(from gitClient: any GitClient) async throws -> Self {
    async let status = gitClient.status()
    async let branches = gitClient.branches()
    async let remotes = gitClient.remotes()
    async let stashes = gitClient.stashes()
    async let tags = gitClient.tags()
    async let worktrees = gitClient.worktrees()
    async let sequencerState = gitClient.sequencerState()
    // Optional metadata: a broken submodule must not fail the refresh.
    async let submodules = try? gitClient.submodules()
    // Optional metadata: a failed probe must not fail the whole refresh.
    async let bisectState = try? gitClient.bisectState()
    async let capabilities = gitClient.capabilities()
    // Optional metadata: an unreadable config must not fail the refresh.
    async let partialCloneRemote = try? gitClient.partialCloneRemote()
    async let isShallow = try? gitClient.isShallowRepository()

    let loadedRemotes = try await remotes
    let remoteBranchesByRemote = try await loadRemoteBranches(
      for: loadedRemotes,
      from: gitClient
    )

    return try await Self(
      status: status,
      branches: branches,
      remotes: loadedRemotes,
      remoteBranchesByRemote: remoteBranchesByRemote,
      stashes: stashes,
      tags: tags,
      worktrees: worktrees,
      submodules: submodules ?? [],
      sequencerState: sequencerState,
      bisectState: bisectState ?? nil,
      capabilities: capabilities,
      partialCloneRemote: partialCloneRemote ?? nil,
      isShallow: isShallow ?? false
    )
  }

  private static func loadRemoteBranches(
    for remotes: [Remote],
    from gitClient: any GitClient
  ) async throws -> [String: [Branch]] {
    try await withThrowingTaskGroup(
      of: (String, [Branch]).self,
      returning: [String: [Branch]].self
    ) { group in
      for remote in remotes {
        group.addTask {
          (remote.name, try await gitClient.remoteBranches(of: remote.name))
        }
      }

      var branchesByRemote: [String: [Branch]] = [:]
      for try await (remoteName, branches) in group {
        branchesByRemote[remoteName] = branches
      }
      return branchesByRemote
    }
  }
}

extension RepositoryModel {
  public func refresh() async {
    await refreshGitState()
    await syncPullRequests()
  }

  /// Refreshes local Git state without waiting for remote pull request synchronization.
  public func refreshGitState() async {
    if let gitRefreshTask {
      await gitRefreshTask.value
      return
    }

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performGitStateRefresh()
    }
    gitRefreshTask = task
    await task.value
    gitRefreshTask = nil
  }

  private func performGitStateRefresh() async {
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      apply(try await RepositoryGitSnapshot.load(from: gitClient))
      // Only clear errors this refresh path produced; a mutation error must
      // survive the refresh that follows the failed operation.
      if lastErrorIsFromBackgroundRead {
        clearError()
      }
    } catch {
      // No snapshot field is applied until every throwing read succeeds.
      lastErrorMessage = error.localizedDescription
      lastErrorIsFromBackgroundRead = true
    }

    if !historyRows.isEmpty {
      await reloadHistory()
    }
  }

  private func apply(_ snapshot: RepositoryGitSnapshot) {
    status = snapshot.status
    changeTrees = ChangeTrees(status: snapshot.status)
    branches = snapshot.branches
    remotes = snapshot.remotes
    remoteBranchesByRemote = snapshot.remoteBranchesByRemote
    stashes = snapshot.stashes
    tags = snapshot.tags
    worktrees = snapshot.worktrees
    submodules = snapshot.submodules
    sequencerState = snapshot.sequencerState
    bisectState = snapshot.bisectState
    gitCapabilities = snapshot.capabilities
    partialCloneRemote = snapshot.partialCloneRemote
    isShallow = snapshot.isShallow
  }
}
