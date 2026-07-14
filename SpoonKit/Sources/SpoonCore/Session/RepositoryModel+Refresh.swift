import Foundation

/// A complete, internally consistent result of the repository's independent git reads.
public struct RepositoryGitSnapshot: Sendable, Hashable {
  public var status: WorkingTreeStatus
  public var branches: [Branch]
  public var remotes: [Remote]
  public var stashes: [Stash]
  public var tags: [Tag]
  public var worktrees: [Worktree]
  public var sequencerState: SequencerState?
  public var supportsBackfill: Bool

  public init(
    status: WorkingTreeStatus,
    branches: [Branch],
    remotes: [Remote],
    stashes: [Stash],
    tags: [Tag],
    worktrees: [Worktree],
    sequencerState: SequencerState?,
    supportsBackfill: Bool
  ) {
    self.status = status
    self.branches = branches
    self.remotes = remotes
    self.stashes = stashes
    self.tags = tags
    self.worktrees = worktrees
    self.sequencerState = sequencerState
    self.supportsBackfill = supportsBackfill
  }

  static func load(from gitClient: any GitClient) async throws -> Self {
    async let status = gitClient.status()
    async let branches = gitClient.branches()
    async let remotes = gitClient.remotes()
    async let stashes = gitClient.stashes()
    async let tags = gitClient.tags()
    async let worktrees = gitClient.worktrees()
    async let sequencerState = gitClient.sequencerState()
    async let supportsBackfill = gitClient.supportsBackfill()

    return try await Self(
      status: status,
      branches: branches,
      remotes: remotes,
      stashes: stashes,
      tags: tags,
      worktrees: worktrees,
      sequencerState: sequencerState,
      supportsBackfill: supportsBackfill
    )
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
      lastErrorMessage = nil
    } catch {
      // No snapshot field is applied until every throwing read succeeds.
      lastErrorMessage = error.localizedDescription
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
    stashes = snapshot.stashes
    tags = snapshot.tags
    worktrees = snapshot.worktrees
    sequencerState = snapshot.sequencerState
    supportsBackfill = snapshot.supportsBackfill
  }
}
