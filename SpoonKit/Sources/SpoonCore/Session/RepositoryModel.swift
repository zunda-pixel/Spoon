public import Foundation
public import Observation

/// Per-window hub tying one repository's git state to the UI.
/// M2 adds file watching, mutations, GitHub sync, and AI services here.
@MainActor
@Observable
public final class RepositoryModel {
  public let repository: Repository

  public private(set) var status: WorkingTreeStatus?
  /// Directory trees for the Changes list, rebuilt alongside `status`.
  public private(set) var changeTrees = ChangeTrees.empty
  public private(set) var branches: [Branch] = []
  public private(set) var remotes: [Remote] = []
  public private(set) var stashes: [Stash] = []
  public private(set) var tags: [Tag] = []
  public private(set) var worktrees: [Worktree] = []
  /// An in-progress rebase / cherry-pick / revert (conflict or edit pause).
  public private(set) var sequencerState: SequencerState?
  public private(set) var isRefreshing = false
  /// A long-running mutation (fetch/pull/push/commit/…) is in flight.
  public private(set) var isBusy = false
  public private(set) var lastErrorMessage: String?

  public func clearError() {
    lastErrorMessage = nil
  }

  /// Set by the New Branch menu command; the window root presents the
  /// sheet and clears it.
  public var isNewBranchSheetRequested = false

  public func requestNewBranchSheet() {
    isNewBranchSheetRequested = true
  }

  private let gitClient: any GitClient
  private let gitHub: GitHubAPIClient?
  /// AI providers keyed by id; injected by AppModel, empty in tests.
  public var aiProviders: [AIProviderID: any CodingAgentProvider] = [:]
  private var watchTask: Task<Void, Never>?

  public init(repository: Repository, gitClient: any GitClient, gitHub: GitHubAPIClient? = nil) {
    self.repository = repository
    self.gitClient = gitClient
    self.gitHub = gitHub
  }

  isolated deinit {
    watchTask?.cancel()
  }

  /// Auto-refreshes on repository changes. Self-inflicted events are
  /// suppressed while a mutation runs; `perform` refreshes afterwards.
  public func startWatching() {
    guard watchTask == nil else { return }
    let root = repository.rootURL
    watchTask = Task { [weak self] in
      for await _ in RepoWatcher.changes(under: root) {
        guard let self else { break }
        if self.isBusy || self.isRefreshing { continue }
        await self.refresh()
      }
    }
  }

  public func stopWatching() {
    watchTask?.cancel()
    watchTask = nil
  }

  // MARK: - AI

  public enum AIActivity: Sendable, Hashable {
    case generatingCommitMessage(AIProviderID)
    case reviewing(AIProviderID)
  }

  public private(set) var aiActivity: AIActivity?
  public private(set) var reviewReport: ReviewReport?
  public private(set) var aiErrorMessage: String?

  public func clearAIError() {
    aiErrorMessage = nil
  }

  public func dismissReview() {
    reviewReport = nil
  }

  /// Generates a commit message from the staged diff. Returns nil on
  /// failure (error surfaced via `aiErrorMessage`).
  public func generateCommitMessage(with providerID: AIProviderID) async -> String? {
    guard let provider = aiProviders[providerID], aiActivity == nil else { return nil }
    aiActivity = .generatingCommitMessage(providerID)
    defer { aiActivity = nil }
    do {
      let diff = try await gitClient.stagedDiffText()
      guard !diff.isEmpty else {
        throw AIError(kind: .nothingToReview)
      }
      let context = PromptBuilder.CommitContext(
        branchName: currentBranch?.name,
        recentSubjects: historyRows.prefix(10).map(\.commit.subject),
        stagedDiff: diff
      )
      let message = try await provider.generateCommitMessage(
        prompt: PromptBuilder.commitMessagePrompt(context)
      )
      aiErrorMessage = nil
      return message
    } catch {
      aiErrorMessage = error.localizedDescription
      return nil
    }
  }

  /// Reviews the current branch against its merge-base with the default
  /// branch; falls back to the working-tree diff on the default branch.
  public func runReview(with providerID: AIProviderID) async {
    guard let provider = aiProviders[providerID], aiActivity == nil else { return }
    aiActivity = .reviewing(providerID)
    defer { aiActivity = nil }
    do {
      let defaultBranch = try await gitClient.defaultBranch()
      let branchName = currentBranch?.name
      let diff: String
      let baseDescription: String
      if let branchName, branchName != defaultBranch {
        let base = try await gitClient.mergeBase(defaultBranch, "HEAD")
        diff = try await gitClient.diffText(from: base.rawValue, to: "HEAD")
        baseDescription = "\(defaultBranch) (merge-base \(base.shortened))"
      } else {
        diff = try await gitClient.stagedDiffText()
        baseDescription = "the index (staged changes)"
      }
      guard !diff.isEmpty else {
        throw AIError(kind: .nothingToReview)
      }
      let context = PromptBuilder.ReviewContext(
        branchName: branchName,
        baseReference: baseDescription,
        diff: diff,
        guidelines: PromptBuilder.guidelines(in: repository.rootURL)
      )
      reviewReport = try await provider.review(
        prompt: PromptBuilder.reviewPrompt(context),
        repository: repository.rootURL
      )
      aiErrorMessage = nil
    } catch {
      aiErrorMessage = error.localizedDescription
    }
  }

  // MARK: - History

  public private(set) var historyRows: [GraphRow] = []
  public private(set) var isLoadingHistory = false
  public private(set) var hasMoreHistory = false
  private var loadedCommits: [Commit] = []
  private var nextHistoryQuery: LogQuery?

  public var currentBranch: Branch? {
    branches.first(where: \.isCurrent)
  }

  /// Count badge for the Changes sidebar row.
  public var pendingChangeCount: Int {
    guard let status else { return 0 }
    return status.entries.count { !$0.isIgnored }
  }

  public func refresh() async {
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      // Independent reads; the client suspends per subprocess, so these
      // genuinely run concurrently and refresh takes one round trip.
      async let status = gitClient.status()
      async let branches = gitClient.branches()
      async let remotes = gitClient.remotes()
      async let stashes = gitClient.stashes()
      async let tags = gitClient.tags()
      async let worktrees = gitClient.worktrees()
      async let sequencerState = gitClient.sequencerState()
      self.status = try await status
      self.branches = try await branches
      self.remotes = try await remotes
      self.stashes = try await stashes
      self.tags = try await tags
      self.worktrees = try await worktrees
      self.sequencerState = try await sequencerState
      changeTrees = self.status.map(ChangeTrees.init) ?? .empty
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = error.localizedDescription
    }
    if !historyRows.isEmpty {
      await reloadHistory()
    }
    await syncPullRequests()
  }

  // MARK: - Pull requests

  public private(set) var prSyncState: PRSyncState = .idle
  public private(set) var openPullRequests: [PullRequest] = []
  /// Local branch name → its open PR, for sidebar badges.
  public private(set) var prByBranch: [String: PullRequest] = [:]

  private var prSyncService: PullRequestSyncService?
  private var prSyncRepoRef: RepoRef?
  private let prSnapshotStore = PullRequestSnapshotStore()
  private var prSnapshotLoaded = false

  /// The GitHub repository this checkout pushes to: `origin` when it is a
  /// GitHub remote, else the first GitHub remote.
  public var gitHubRepoRef: RepoRef? {
    let candidates = remotes.sorted { $0.name == "origin" && $1.name != "origin" }
    return candidates.lazy
      .compactMap { RemoteURLParser.gitHubRepo(from: $0.pushURL ?? $0.fetchURL) }
      .first
  }

  /// One paginated fetch of all open PRs, joined locally against branches.
  /// TTL-cached (60 s) unless forced; failures never disturb git state.
  public func syncPullRequests(force: Bool = false) async {
    guard let gitHub else { return }
    guard let repoRef = gitHubRepoRef else {
      prSyncState = .noGitHubRemote
      openPullRequests = []
      prByBranch = [:]
      return
    }
    if prSyncService == nil || prSyncRepoRef != repoRef {
      prSyncService = PullRequestSyncService(client: gitHub, repoRef: repoRef)
      prSyncRepoRef = repoRef
    }
    guard let service = prSyncService else { return }

    // Cold start: show the last session's snapshot instantly while the
    // first network sync runs.
    if !prSnapshotLoaded {
      prSnapshotLoaded = true
      if openPullRequests.isEmpty,
        let snapshot = prSnapshotStore.load(repositoryID: repository.id)
      {
        applyPullRequests(snapshot.pullRequests)
      }
    }

    prSyncState = .syncing
    do {
      let pullRequests = try await service.openPullRequests(force: force)
      applyPullRequests(pullRequests)
      prSnapshotStore.save(pullRequests, repositoryID: repository.id)
      prSyncState = .synced(Date())
    } catch let error as GitHubError {
      switch error.kind {
      case .unauthenticated:
        prSyncState = .unauthenticated
      case .rateLimited(let resetAt):
        prSyncState = .rateLimited(until: resetAt)
      default:
        prSyncState = .failed(error.localizedDescription)
      }
    } catch {
      prSyncState = .failed(error.localizedDescription)
    }
  }

  private func applyPullRequests(_ pullRequests: [PullRequest]) {
    let owners = Set(
      remotes.compactMap { RemoteURLParser.gitHubRepo(from: $0.pushURL ?? $0.fetchURL)?.owner }
    )
    openPullRequests = pullRequests
    prByBranch = BranchPRLinker.link(
      branches: branches,
      pullRequests: pullRequests,
      remoteOwners: owners
    )
  }

  // MARK: - Diffs

  public enum ChangeArea: Sendable, Hashable {
    case staged
    case unstaged
    case untracked
    case conflicted
  }

  /// Identifies one row in the Changes list for the detail column.
  public struct FileSelection: Sendable, Hashable {
    public var path: String
    public var area: ChangeArea

    public init(path: String, area: ChangeArea) {
      self.path = path
      self.area = area
    }
  }

  public func diff(for selection: FileSelection) async throws -> [FileDiff] {
    switch selection.area {
    case .staged:
      try await gitClient.diffWorkingTree(path: selection.path, staged: true)
    case .unstaged, .conflicted:
      try await gitClient.diffWorkingTree(path: selection.path, staged: false)
    case .untracked:
      [try await gitClient.untrackedFileDiff(path: selection.path)]
    }
  }

  public func commitDetail(_ oid: ObjectID) async throws -> CommitDetail {
    try await gitClient.commitDetail(oid)
  }

  // MARK: - Operations

  public func stage(paths: [String]) async {
    await perform { try await $0.stage(paths: paths) }
  }

  public func unstage(paths: [String]) async {
    await perform { try await $0.unstage(paths: paths) }
  }

  /// Destructive: drops working-tree edits for `paths`.
  public func discardWorkingTree(paths: [String]) async {
    await perform { try await $0.discardWorkingTree(paths: paths) }
  }

  /// Destructive: deletes untracked files.
  public func deleteUntracked(paths: [String]) async {
    await perform { try await $0.deleteUntracked(paths: paths) }
  }

  public func stageHunk(_ hunkID: Hunk.ID, of diff: FileDiff) async {
    guard let patch = DiffPatchBuilder.patch(for: diff, including: [hunkID]) else { return }
    await perform { try await $0.applyPatch(patch, reverse: false, toIndex: true) }
  }

  public func unstageHunk(_ hunkID: Hunk.ID, of diff: FileDiff) async {
    guard let patch = DiffPatchBuilder.patch(for: diff, including: [hunkID]) else { return }
    await perform { try await $0.applyPatch(patch, reverse: true, toIndex: true) }
  }

  /// Destructive: reverts only the selected changed lines of one hunk in
  /// the working tree.
  public func discardLines(_ offsets: Set<Int>, of hunkID: Hunk.ID, in diff: FileDiff) async {
    guard
      let patch = DiffPatchBuilder.discardPatch(
        for: diff, hunkID: hunkID, selectedOffsets: offsets)
    else { return }
    await perform { try await $0.applyPatch(patch, reverse: true, toIndex: false) }
  }

  /// Destructive: reverts one whole hunk in the working tree.
  public func discardHunk(_ hunkID: Hunk.ID, of diff: FileDiff) async {
    guard let hunk = diff.hunks.first(where: { $0.id == hunkID }) else { return }
    await discardLines(DiffPatchBuilder.changedLineOffsets(of: hunk), of: hunkID, in: diff)
  }

  /// Removes only the selected changed lines of one hunk from the index,
  /// leaving the working tree untouched. `diff` must be a staged diff.
  public func unstageLines(_ offsets: Set<Int>, of hunkID: Hunk.ID, in diff: FileDiff) async {
    guard
      let patch = DiffPatchBuilder.discardPatch(
        for: diff, hunkID: hunkID, selectedOffsets: offsets)
    else { return }
    await perform { try await $0.applyPatch(patch, reverse: true, toIndex: true) }
  }

  public func commit(message: String, amend: Bool = false) async -> Bool {
    await perform { try await $0.commit(message: message, amend: amend) }
  }

  public func remoteBranches(of remoteName: String) async throws -> [Branch] {
    try await gitClient.remoteBranches(of: remoteName)
  }

  public func addRemote(name: String, url: String) async {
    await perform { try await $0.addRemote(name: name, url: url) }
  }

  public func removeRemote(name: String) async {
    await perform { try await $0.removeRemote(name: name) }
  }

  public func checkout(branch: String) async {
    await perform { try await $0.checkout(branch: branch) }
  }

  /// Checks out a commit directly (detached HEAD).
  public func checkoutRevision(_ oid: ObjectID) async {
    await perform { try await $0.checkoutRevision(oid) }
  }

  /// Merges `branch` into the current branch; `squash` stages the combined
  /// changes for a separate commit.
  public func merge(branch: String, squash: Bool = false) async {
    await perform { try await $0.merge(branch: branch, squash: squash) }
  }

  // MARK: - Tags

  public func createTag(name: String, at target: ObjectID?, message: String?) async {
    await perform { try await $0.createTag(name: name, at: target, message: message) }
  }

  public func deleteTag(name: String) async {
    await perform { try await $0.deleteTag(name: name) }
  }

  public func createBranch(
    name: String, from startPoint: String? = nil, checkout: Bool = true
  ) async {
    await perform { try await $0.createBranch(name: name, from: startPoint, checkout: checkout) }
  }

  public func checkoutRemoteBranch(_ remoteBranch: String) async {
    await perform { try await $0.checkoutRemoteBranch(remoteBranch) }
  }

  /// Destructive: deletes a local branch (`-D` when `force`).
  public func deleteBranch(name: String, force: Bool = false) async {
    await perform { try await $0.deleteBranch(name: name, force: force) }
  }

  public func renameBranch(from oldName: String, to newName: String) async {
    await perform { try await $0.renameBranch(from: oldName, to: newName) }
  }

  // MARK: - Worktrees

  /// The linked worktree that has `branch` checked out, if any.
  public func worktree(for branch: Branch) -> Worktree? {
    worktrees.first { !$0.isMain && $0.branch == branch.name }
  }

  public func addWorktree(path: URL, branch: String) async {
    await perform { try await $0.addWorktree(path: path, branch: branch) }
  }

  /// Destructive when `force`: discards the worktree's local changes.
  public func removeWorktree(path: URL, force: Bool = false) async {
    await perform { try await $0.removeWorktree(path: path, force: force) }
  }

  // MARK: - Sequencer (rebase / cherry-pick / revert)

  public var isSequencing: Bool { sequencerState != nil }

  /// Builds the editable rebase plan whose oldest step is `commit`.
  public func rebasePlan(from commit: Commit) async throws -> RebasePlan {
    guard sequencerState == nil else { throw RebaseSetupError.sequencerActive }
    guard let status else { throw RebaseSetupError.workingTreeNotClean }
    guard status.headBranch != nil else { throw RebaseSetupError.detachedHead }
    guard
      status.stagedEntries.isEmpty,
      status.unstagedEntries.isEmpty,
      status.conflictedEntries.isEmpty
    else { throw RebaseSetupError.workingTreeNotClean }

    let baseOID = commit.parents.first
    let reference = baseOID.map { "\($0.rawValue)..HEAD" } ?? "HEAD"
    let page = try await gitClient.log(LogQuery(reference: reference, maxCount: 1000))
    guard !page.hasMore else { throw RebaseSetupError.rangeTooLarge }
    guard !page.commits.contains(where: \.isMerge) else { throw RebaseSetupError.mergeInRange }
    return RebasePlan(
      steps: page.commits.reversed().map { RebaseStep(action: .pick, commit: $0) },
      baseOID: baseOID
    )
  }

  @discardableResult
  public func interactiveRebase(_ plan: RebasePlan) async -> Bool {
    await perform { try await $0.interactiveRebase(plan) }
  }

  public func cherryPick(_ oid: ObjectID) async {
    await perform { try await $0.cherryPick(oid) }
  }

  public func revert(_ oid: ObjectID) async {
    await perform { try await $0.revert(oid) }
  }

  public func continueSequencer() async {
    guard let kind = sequencerState?.kind else { return }
    await perform { try await $0.continueSequencer(kind) }
  }

  public func skipSequencer() async {
    // `git merge` has no --skip.
    guard let kind = sequencerState?.kind, kind != .merge else { return }
    await perform { try await $0.skipSequencer(kind) }
  }

  /// Destructive: throws away the sequencer's applied work so far.
  public func abortSequencer() async {
    guard let kind = sequencerState?.kind else { return }
    await perform { try await $0.abortSequencer(kind) }
  }

  public func fetch() async {
    await perform { try await $0.fetch() }
    await syncPullRequests(force: true)
  }

  public func pull() async {
    await perform { try await $0.pull() }
  }

  public func push(force: Bool = false) async {
    await perform { try await $0.push(force: force) }
    await syncPullRequests(force: true)
  }

  public func saveStash(message: String?, includeUntracked: Bool) async {
    await perform { try await $0.saveStash(message: message, includeUntracked: includeUntracked) }
  }

  public func applyStash(_ stash: Stash, pop: Bool) async {
    await perform { try await $0.applyStash(stash, pop: pop) }
  }

  public func dropStash(_ stash: Stash) async {
    await perform { try await $0.dropStash(stash) }
  }

  public func stashDiffs(_ stash: Stash) async throws -> [FileDiff] {
    try await gitClient.stashDiffs(stash)
  }

  /// Runs one mutation with busy-state, error capture, and a single
  /// refresh afterwards. Returns whether the operation succeeded.
  @discardableResult
  private func perform(_ operation: (any GitClient) async throws -> Void) async -> Bool {
    isBusy = true
    var succeeded = false
    do {
      try await operation(gitClient)
      lastErrorMessage = nil
      succeeded = true
    } catch {
      lastErrorMessage = error.localizedDescription
    }
    isBusy = false
    await refresh()
    return succeeded
  }

  public func loadHistoryIfNeeded() async {
    guard historyRows.isEmpty, !isLoadingHistory else { return }
    await reloadHistory()
  }

  public func reloadHistory() async {
    // No commits yet (unborn branch) — `git log HEAD` would fail.
    guard status?.headOID != nil else {
      historyRows = []
      loadedCommits = []
      hasMoreHistory = false
      return
    }
    loadedCommits = []
    nextHistoryQuery = LogQuery()
    await loadMoreHistory(replacing: true)
  }

  public func loadMoreHistory() async {
    await loadMoreHistory(replacing: false)
  }

  private func loadMoreHistory(replacing: Bool) async {
    guard let query = nextHistoryQuery, !isLoadingHistory else { return }
    isLoadingHistory = true
    defer { isLoadingHistory = false }
    do {
      let page = try await gitClient.log(query)
      loadedCommits.append(contentsOf: page.commits)
      hasMoreHistory = page.hasMore
      nextHistoryQuery = page.hasMore ? query.next() : nil
      // Lane assignment depends on the whole loaded prefix, so recompute
      // over all pages; ~thousands of commits stay well under a frame.
      historyRows = CommitGraphLayout.assignLanes(loadedCommits)
      lastErrorMessage = nil
    } catch {
      if replacing {
        historyRows = []
      }
      lastErrorMessage = error.localizedDescription
    }
  }
}
