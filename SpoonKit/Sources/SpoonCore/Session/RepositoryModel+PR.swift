extension RepositoryModel {
  public var prSyncState: PRSyncState { pullRequestStore.syncState }
  public var openPullRequests: [PullRequest] { pullRequestStore.openPullRequests }
  public var prByBranch: [String: PullRequest] { pullRequestStore.pullRequestByBranch }

  /// The GitHub repository this checkout pushes to: `origin` when it is a
  /// GitHub remote, else the first GitHub remote.
  public var gitHubRepoRef: RepoRef? {
    PullRequestStore.gitHubRepoRef(remotes: remotes)
  }

  /// One paginated fetch of all open PRs, joined locally against branches.
  /// TTL-cached (60 s) unless forced; failures never disturb git state.
  public func syncPullRequests(force: Bool = false) async {
    await pullRequestStore.sync(
      branches: branches,
      remotes: remotes,
      force: force
    )
  }
}
