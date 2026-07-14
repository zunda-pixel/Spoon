import Foundation
import Observation

/// Owns GitHub pull-request synchronization and branch linking.
@MainActor
@Observable
final class PullRequestStore {
  private(set) var syncState: PRSyncState = .idle
  private(set) var openPullRequests: [PullRequest] = []
  /// Local branch name → its open PR, for sidebar badges.
  private(set) var pullRequestByBranch: [String: PullRequest] = [:]

  private let repositoryID: Repository.ID
  private let gitHub: GitHubAPIClient?
  private let snapshotStore: PullRequestSnapshotStore
  private var syncService: PullRequestSyncService?
  private var syncRepoRef: RepoRef?
  private var snapshotLoaded = false
  private var syncTask: Task<Void, Never>?
  private var syncGeneration = 0

  init(
    repositoryID: Repository.ID,
    gitHub: GitHubAPIClient?,
    snapshotStore: PullRequestSnapshotStore = PullRequestSnapshotStore()
  ) {
    self.repositoryID = repositoryID
    self.gitHub = gitHub
    self.snapshotStore = snapshotStore
  }

  func sync(branches: [Branch], remotes: [Remote], force: Bool) async {
    let predecessor = syncTask
    syncGeneration += 1
    let generation = syncGeneration
    let task = Task { @MainActor [weak self] in
      if let predecessor {
        await predecessor.value
      }
      guard let self else { return }
      await self.performSync(branches: branches, remotes: remotes, force: force)
    }
    syncTask = task
    await task.value
    if syncGeneration == generation {
      syncTask = nil
    }
  }

  private func performSync(branches: [Branch], remotes: [Remote], force: Bool) async {
    guard let gitHub else { return }
    guard let repoRef = Self.gitHubRepoRef(remotes: remotes) else {
      syncState = .noGitHubRemote
      openPullRequests = []
      pullRequestByBranch = [:]
      return
    }
    if syncService == nil || syncRepoRef != repoRef {
      syncService = PullRequestSyncService(client: gitHub, repoRef: repoRef)
      syncRepoRef = repoRef
    }
    guard let service = syncService else { return }

    if !snapshotLoaded {
      snapshotLoaded = true
      if openPullRequests.isEmpty,
        let snapshot = snapshotStore.load(repositoryID: repositoryID)
      {
        apply(snapshot.pullRequests, branches: branches, remotes: remotes)
      }
    }

    syncState = .syncing
    do {
      let pullRequests = try await service.openPullRequests(force: force)
      apply(pullRequests, branches: branches, remotes: remotes)
      snapshotStore.save(pullRequests, repositoryID: repositoryID)
      syncState = .synced(Date())
    } catch let error as GitHubError {
      switch error.kind {
      case .unauthenticated:
        syncState = .unauthenticated
      case .rateLimited(let resetAt):
        syncState = .rateLimited(until: resetAt)
      default:
        syncState = .failed(error.localizedDescription)
      }
    } catch {
      syncState = .failed(error.localizedDescription)
    }
  }

  static func gitHubRepoRef(remotes: [Remote]) -> RepoRef? {
    let candidates = remotes.sorted { $0.name == "origin" && $1.name != "origin" }
    return candidates.lazy
      .compactMap { RemoteURLParser.gitHubRepo(from: $0.pushURL ?? $0.fetchURL) }
      .first
  }

  private func apply(
    _ pullRequests: [PullRequest],
    branches: [Branch],
    remotes: [Remote]
  ) {
    let owners = Set(
      remotes.compactMap { RemoteURLParser.gitHubRepo(from: $0.pushURL ?? $0.fetchURL)?.owner }
    )
    openPullRequests = pullRequests
    pullRequestByBranch = BranchPRLinker.link(
      branches: branches,
      pullRequests: pullRequests,
      remoteOwners: owners
    )
  }
}
