import Foundation
import Testing

@testable import SpoonCore

@MainActor
@Suite("RepositoryModel")
struct RepositoryModelTests {
  @Test func refreshAppliesACompleteSnapshot() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("11111111")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("main", oid: oid, isCurrent: true)]
    )
    let model = makeModel(client)

    await model.refresh()

    #expect(model.status?.headOID == oid)
    #expect(model.currentBranch?.name == "main")
    #expect(model.lastErrorMessage == nil)
  }

  @Test func gitStateRefreshAppliesAtomicallyWithoutPullRequestSync() async {
    let client = FakeRepositoryGitClient()
    let originalOID = makeOID("12121212")
    await client.configure(
      status: makeStatus(oid: originalOID, branch: "main"),
      branches: [makeBranch("main", oid: originalOID, isCurrent: true)]
    )
    let model = makeModel(client)

    await model.refreshGitState()

    #expect(model.status?.headOID == originalOID)
    #expect(model.currentBranch?.name == "main")
    #expect(model.lastErrorMessage == nil)

    let replacementOID = makeOID("13131313")
    await client.configure(
      status: makeStatus(oid: replacementOID, branch: "replacement"),
      branches: [makeBranch("replacement", oid: replacementOID, isCurrent: true)],
      failBranches: true
    )

    await model.refreshGitState()

    #expect(model.status?.headOID == originalOID)
    #expect(model.currentBranch?.name == "main")
    #expect(model.lastErrorMessage == FakeRepositoryGitClient.Failure.refresh.localizedDescription)
  }

  @Test func mutationRefreshesTheWorkingTree() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("22222222")
    await client.configure(
      status: WorkingTreeStatus(
        headOID: oid,
        headBranch: "main",
        entries: [FileStatusEntry(path: "note.txt", isUntracked: true)]
      ),
      branches: [makeBranch("main", oid: oid, isCurrent: true)]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.stage(paths: ["note.txt"])

    #expect(await client.stageCallCount == 1)
    #expect(model.status?.stagedEntries.map(\.path) == ["note.txt"])
    #expect(model.status?.untrackedEntries.isEmpty == true)
  }

  @Test func remoteBranchesRefreshAtomicallyWithRepositoryState() async {
    let client = FakeRepositoryGitClient()
    let originalOID = makeOID("23232323")
    let originalRemoteBranch = makeBranch(
      "origin/main",
      oid: originalOID,
      isCurrent: false
    )
    await client.configure(
      status: makeStatus(oid: originalOID, branch: "main"),
      branches: [makeBranch("main", oid: originalOID, isCurrent: true)],
      remotes: [Remote(name: "origin", fetchURL: "https://example.com/repo.git")],
      remoteBranchesByRemote: ["origin": [originalRemoteBranch]]
    )
    let model = makeModel(client)

    await model.refreshGitState()

    #expect(model.remoteBranchesByRemote["origin"] == [originalRemoteBranch])

    let replacementOID = makeOID("24242424")
    await client.configure(
      status: makeStatus(oid: replacementOID, branch: "replacement"),
      branches: [makeBranch("replacement", oid: replacementOID, isCurrent: true)],
      remotes: [Remote(name: "origin", fetchURL: "https://example.com/repo.git")],
      remoteBranchesByRemote: [
        "origin": [makeBranch("origin/replacement", oid: replacementOID, isCurrent: false)]
      ],
      failRemoteBranches: true
    )

    await model.refreshGitState()

    #expect(model.status?.headOID == originalOID)
    #expect(model.remoteBranchesByRemote["origin"] == [originalRemoteBranch])
    #expect(model.lastErrorMessage == FakeRepositoryGitClient.Failure.refresh.localizedDescription)
  }

  @Test func localRenameCanRenameItsRemoteUpstream() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("25252525")
    await client.configure(
      status: makeStatus(oid: oid, branch: "old"),
      branches: [makeBranch("old", oid: oid, isCurrent: true, upstream: "origin/old")]
    )
    let model = makeModel(client)

    await model.renameBranch(
      from: "old",
      to: "new",
      renameRemoteUpstream: "origin/old"
    )

    #expect(
      await client.mutationCalls == [
        "rename-local:old:new",
        "rename-remote:origin:old:new",
        "upstream:new:origin/new",
      ]
    )
  }

  @Test func localDeleteCanDeleteItsRemoteUpstream() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("26262626")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("topic", oid: oid, isCurrent: false, upstream: "origin/topic")]
    )
    let model = makeModel(client)

    await model.deleteBranch(
      name: "topic",
      force: true,
      deleteRemoteUpstream: "origin/topic"
    )

    #expect(
      await client.mutationCalls == [
        "delete-local:topic:true",
        "delete-remote:origin:topic",
      ]
    )
  }

  @Test func worktreeCreationReportsSuccessAndFailure() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("27272727")
    let status = makeStatus(oid: oid, branch: "main")
    let branches = [makeBranch("main", oid: oid, isCurrent: true)]
    await client.configure(status: status, branches: branches)
    let model = makeModel(client)
    let firstPath = URL(filePath: "/tmp/worktree-success")

    let succeeded = await model.addWorktree(path: firstPath, branch: "topic")
    let remotePath = URL(filePath: "/tmp/remote-worktree-success")
    let remoteSucceeded = await model.addWorktree(
      path: remotePath,
      remoteBranch: "origin/remote-topic",
      localBranch: "remote-topic"
    )

    #expect(succeeded)
    #expect(remoteSucceeded)
    #expect(
      await client.mutationCalls == [
        "add-worktree:\(firstPath.path):topic",
        "add-remote-worktree:\(remotePath.path):origin/remote-topic:remote-topic",
      ]
    )

    await client.configure(
      status: status,
      branches: branches,
      failWorktreeMutations: true
    )
    let failed = await model.addWorktree(
      path: URL(filePath: "/tmp/worktree-failure"),
      branch: "other"
    )

    #expect(!failed)
    #expect(
      model.lastErrorMessage
        == FakeRepositoryGitClient.Failure.unimplemented.localizedDescription
    )
  }

  @Test func worktreeRemovalCanDeleteItsBranchInOrder() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("28282828")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [
        makeBranch("main", oid: oid, isCurrent: true),
        makeBranch("topic", oid: oid, isCurrent: false),
      ]
    )
    let model = makeModel(client)
    let firstPath = URL(filePath: "/tmp/worktree-only")
    let secondPath = URL(filePath: "/tmp/worktree-and-branch")

    await model.removeWorktree(path: firstPath)
    await model.removeWorktree(
      path: secondPath,
      force: true,
      deleteBranch: "topic",
      forceDeleteBranch: true
    )

    #expect(
      await client.mutationCalls == [
        "remove-worktree:\(firstPath.path):false",
        "remove-worktree:\(secondPath.path):true",
        "delete-local:topic:true",
      ]
    )
  }

  @Test func historyLoadsSubsequentPages() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("33333333")
    let first = makeCommit("33333333", subject: "first")
    let second = makeCommit("44444444", subject: "second")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      logPages: [
        0: LogPage(commits: [first], hasMore: true),
        500: LogPage(commits: [second], hasMore: false),
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.loadHistoryIfNeeded()
    #expect(model.historyRows.map(\.commit.subject) == ["first"])
    #expect(model.hasMoreHistory)

    await model.loadMoreHistory()
    #expect(model.historyRows.map(\.commit.subject) == ["first", "second"])
    #expect(!model.hasMoreHistory)
  }

  @Test func historyLoadsTheSelectedReferenceAndPreservesItAcrossPages() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("77777777")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      logPages: [
        0: LogPage(commits: [makeCommit("77777777", subject: "feature")], hasMore: true),
        500: LogPage(commits: [], hasMore: false),
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.loadHistoryIfNeeded(reference: "feature/topic")
    await model.loadMoreHistory()

    #expect(await client.logQueries.map(\.reference) == ["feature/topic", "feature/topic"])
  }

  @Test func failedRefreshPreservesThePreviousSnapshot() async {
    let client = FakeRepositoryGitClient()
    let originalOID = makeOID("55555555")
    await client.configure(
      status: makeStatus(oid: originalOID, branch: "main"),
      branches: [makeBranch("main", oid: originalOID, isCurrent: true)]
    )
    let model = makeModel(client)
    await model.refresh()

    let replacementOID = makeOID("66666666")
    await client.configure(
      status: makeStatus(oid: replacementOID, branch: "replacement"),
      branches: [makeBranch("replacement", oid: replacementOID, isCurrent: true)],
      failBranches: true
    )
    await model.refresh()

    #expect(model.status?.headOID == originalOID)
    #expect(model.currentBranch?.name == "main")
    #expect(model.lastErrorMessage == FakeRepositoryGitClient.Failure.refresh.localizedDescription)
  }

  @Test func failedMutationErrorSurvivesTheFollowUpRefresh() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("88888888")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("main", oid: oid, isCurrent: true)]
    )
    let model = makeModel(client)
    await model.refresh()

    let succeeded = await model.commit(message: "message")

    #expect(!succeeded)
    #expect(
      model.lastErrorMessage
        == FakeRepositoryGitClient.Failure.unimplemented.localizedDescription
    )

    await model.refresh()
    #expect(
      model.lastErrorMessage
        == FakeRepositoryGitClient.Failure.unimplemented.localizedDescription
    )

    model.clearError()
    #expect(model.lastErrorMessage == nil)
  }

  @Test func refreshFallsBackToHeadHistoryWhenTheReferenceDisappears() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("aaaaaaaa")
    let page = LogPage(commits: [makeCommit("aaaaaaaa", subject: "tip")], hasMore: false)
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [
        makeBranch("main", oid: oid, isCurrent: true),
        makeBranch("topic", oid: oid, isCurrent: false),
      ],
      logPages: [0: page]
    )
    let model = makeModel(client)
    await model.refresh()
    await model.loadHistoryIfNeeded(reference: "topic")
    #expect(model.historyRows.count == 1)

    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("main", oid: oid, isCurrent: true)],
      logPages: [0: page]
    )
    await model.refreshGitState()

    #expect(await client.logQueries.map(\.reference) == ["topic", nil])
    #expect(model.lastErrorMessage == nil)
    #expect(model.historyRows.count == 1)
  }

  @Test func forceDeleteIsOnlyRequiredForUnmergedBranches() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("11112222")
    let mergedOID = makeOID("33334444")
    let unmergedOID = makeOID("55556666")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      mergeBases: ["merged...HEAD": mergedOID, "unmerged...HEAD": head]
    )
    let model = makeModel(client)
    await model.refresh()

    let pushed = makeBranch(
      "pushed", oid: unmergedOID, isCurrent: false, upstream: "origin/pushed", ahead: 0
    )
    #expect(await model.requiresForceDelete(pushed) == false)

    let atHead = makeBranch("at-head", oid: head, isCurrent: false)
    #expect(await model.requiresForceDelete(atHead) == false)

    let merged = makeBranch("merged", oid: mergedOID, isCurrent: false)
    #expect(await model.requiresForceDelete(merged) == false)

    let unmerged = makeBranch("unmerged", oid: unmergedOID, isCurrent: false)
    #expect(await model.requiresForceDelete(unmerged) == true)
  }

  @Test func refreshErrorClearsOnceRefreshRecovers() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("99999999")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("main", oid: oid, isCurrent: true)],
      failBranches: true
    )
    let model = makeModel(client)

    await model.refresh()
    #expect(model.lastErrorMessage == FakeRepositoryGitClient.Failure.refresh.localizedDescription)

    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("main", oid: oid, isCurrent: true)]
    )

    await model.refresh()
    #expect(model.lastErrorMessage == nil)
  }

  private func makeModel(_ client: FakeRepositoryGitClient) -> RepositoryModel {
    RepositoryModel(
      repository: Repository(rootURL: URL(filePath: "/tmp/repository-model-tests")),
      gitClient: client
    )
  }

  private func makeStatus(oid: ObjectID, branch: String) -> WorkingTreeStatus {
    WorkingTreeStatus(headOID: oid, headBranch: branch)
  }

  private func makeBranch(
    _ name: String,
    oid: ObjectID,
    isCurrent: Bool,
    upstream: String? = nil,
    ahead: Int? = nil
  ) -> Branch {
    Branch(
      name: name,
      isCurrent: isCurrent,
      tip: oid,
      subject: name,
      upstream: upstream,
      ahead: ahead,
      behind: nil,
      committedAt: nil
    )
  }

  private func makeCommit(_ oid: String, subject: String) -> Commit {
    Commit(
      oid: makeOID(oid),
      parents: [],
      subject: subject,
      authorName: "Tester",
      authorEmail: "tester@example.com",
      authoredAt: .distantPast,
      committedAt: .distantPast
    )
  }

  private func makeOID(_ value: String) -> ObjectID {
    ObjectID(rawValue: value)!
  }
}

private actor FakeRepositoryGitClient: GitClient {
  enum Failure: LocalizedError {
    case refresh
    case unimplemented

    var errorDescription: String? {
      switch self {
      case .refresh: "Refresh failed"
      case .unimplemented: "Not implemented by RepositoryModelTests fake"
      }
    }
  }

  nonisolated let repositoryRoot = URL(filePath: "/tmp/repository-model-tests")

  private var currentStatus = WorkingTreeStatus()
  private var currentBranches: [Branch] = []
  private var currentRemotes: [Remote] = []
  private var currentRemoteBranchesByRemote: [String: [Branch]] = [:]
  private var pages: [Int: LogPage] = [:]
  private var mergeBases: [String: ObjectID] = [:]
  private var shouldFailBranches = false
  private var shouldFailRemoteBranches = false
  private var shouldFailWorktreeMutations = false
  private(set) var stageCallCount = 0
  private(set) var logQueries: [LogQuery] = []
  private(set) var mutationCalls: [String] = []

  func configure(
    status: WorkingTreeStatus,
    branches: [Branch],
    remotes: [Remote] = [],
    remoteBranchesByRemote: [String: [Branch]] = [:],
    logPages: [Int: LogPage] = [:],
    mergeBases: [String: ObjectID] = [:],
    failBranches: Bool = false,
    failRemoteBranches: Bool = false,
    failWorktreeMutations: Bool = false
  ) {
    currentStatus = status
    currentBranches = branches
    currentRemotes = remotes
    currentRemoteBranchesByRemote = remoteBranchesByRemote
    pages = logPages
    self.mergeBases = mergeBases
    shouldFailBranches = failBranches
    shouldFailRemoteBranches = failRemoteBranches
    shouldFailWorktreeMutations = failWorktreeMutations
  }

  func status() async throws -> WorkingTreeStatus { currentStatus }

  func branches() async throws -> [Branch] {
    if shouldFailBranches { throw Failure.refresh }
    return currentBranches
  }

  func remotes() async throws -> [Remote] { currentRemotes }
  func stashes() async throws -> [Stash] { [] }
  func tags() async throws -> [SpoonCore.Tag] { [] }
  func worktrees() async throws -> [Worktree] { [] }
  func sequencerState() async throws -> SequencerState? { nil }
  func supportsBackfill() async -> Bool { false }

  func stage(paths: [String]) async throws {
    stageCallCount += 1
    currentStatus.entries = currentStatus.entries.map { entry in
      guard paths.contains(entry.path) else { return entry }
      var updated = entry
      updated.staged = .added
      updated.isUntracked = false
      return updated
    }
  }

  func log(_ query: LogQuery) async throws -> LogPage {
    logQueries.append(query)
    return pages[query.skip] ?? LogPage(commits: [], hasMore: false)
  }

  func diffWorkingTree(path: String?, staged: Bool) async throws -> [FileDiff] { [] }
  func untrackedFileDiff(path: String) async throws -> FileDiff { throw Failure.unimplemented }
  func unstage(paths: [String]) async throws { throw Failure.unimplemented }
  func applyPatch(_ patch: String, reverse: Bool, toIndex: Bool) async throws {
    throw Failure.unimplemented
  }
  func discardWorkingTree(paths: [String]) async throws { throw Failure.unimplemented }
  func deleteUntracked(paths: [String]) async throws { throw Failure.unimplemented }
  func commit(message: String, amend: Bool) async throws { throw Failure.unimplemented }
  func reset(to target: ObjectID, mode: ResetMode) async throws { throw Failure.unimplemented }
  func commitDetail(_ oid: ObjectID) async throws -> CommitDetail { throw Failure.unimplemented }
  func reflog(maxCount: Int, skip: Int) async throws -> [ReflogEntry] { [] }
  func switchBranch(_ branch: String) async throws { throw Failure.unimplemented }
  func switchToRevision(_ oid: ObjectID) async throws { throw Failure.unimplemented }
  func createBranch(
    name: String,
    from startPoint: String?,
    switchToBranch: Bool
  ) async throws {
    throw Failure.unimplemented
  }
  func switchToRemoteBranch(_ remoteBranch: String) async throws { throw Failure.unimplemented }
  func merge(branch: String, options: MergeOptions) async throws { throw Failure.unimplemented }
  func deleteBranch(name: String, force: Bool) async throws {
    mutationCalls.append("delete-local:\(name):\(force)")
  }
  func renameBranch(from oldName: String, to newName: String) async throws {
    mutationCalls.append("rename-local:\(oldName):\(newName)")
  }
  func setUpstream(of branch: String, to upstream: String) async throws {
    mutationCalls.append("upstream:\(branch):\(upstream)")
  }
  func defaultBranch() async throws -> String { "main" }
  func remoteBranches(of remoteName: String) async throws -> [Branch] {
    if shouldFailRemoteBranches { throw Failure.refresh }
    return currentRemoteBranchesByRemote[remoteName] ?? []
  }
  func addRemote(name: String, url: String) async throws { throw Failure.unimplemented }
  func setRemoteURL(name: String, fetchURL: String, pushURL: String?) async throws {
    throw Failure.unimplemented
  }
  func removeRemote(name: String) async throws { throw Failure.unimplemented }
  func renameRemoteBranch(
    remoteName: String,
    from oldName: String,
    to newName: String
  ) async throws {
    mutationCalls.append("rename-remote:\(remoteName):\(oldName):\(newName)")
  }
  func deleteRemoteBranch(name: String, from remoteName: String) async throws {
    mutationCalls.append("delete-remote:\(remoteName):\(name)")
  }
  func fetch() async throws { throw Failure.unimplemented }
  func backfill() async throws { throw Failure.unimplemented }
  func pull() async throws { throw Failure.unimplemented }
  func push(force: Bool) async throws { throw Failure.unimplemented }
  func createTag(name: String, at target: ObjectID?, message: String?) async throws {
    throw Failure.unimplemented
  }
  func deleteTag(name: String) async throws { throw Failure.unimplemented }
  func pushTag(name: String, to remoteName: String) async throws { throw Failure.unimplemented }
  func pushAllTags(to remoteName: String) async throws { throw Failure.unimplemented }
  func deleteRemoteTag(name: String, from remoteName: String) async throws {
    throw Failure.unimplemented
  }
  func addWorktree(path: URL, branch: String) async throws {
    if shouldFailWorktreeMutations { throw Failure.unimplemented }
    mutationCalls.append("add-worktree:\(path.path):\(branch)")
  }
  func addWorktree(
    path: URL,
    remoteBranch: String,
    localBranch: String
  ) async throws {
    if shouldFailWorktreeMutations { throw Failure.unimplemented }
    mutationCalls.append(
      "add-remote-worktree:\(path.path):\(remoteBranch):\(localBranch)"
    )
  }
  func removeWorktree(path: URL, force: Bool) async throws {
    if shouldFailWorktreeMutations { throw Failure.unimplemented }
    mutationCalls.append("remove-worktree:\(path.path):\(force)")
  }
  func sparseCheckoutPaths() async throws -> [String]? { nil }
  func setSparseCheckout(paths: [String]) async throws { throw Failure.unimplemented }
  func disableSparseCheckout() async throws { throw Failure.unimplemented }
  func interactiveRebase(_ plan: RebasePlan) async throws { throw Failure.unimplemented }
  func cherryPick(_ oid: ObjectID) async throws { throw Failure.unimplemented }
  func revert(_ oid: ObjectID) async throws { throw Failure.unimplemented }
  func continueSequencer(_ kind: SequencerState.Kind) async throws { throw Failure.unimplemented }
  func skipSequencer(_ kind: SequencerState.Kind) async throws { throw Failure.unimplemented }
  func abortSequencer(_ kind: SequencerState.Kind) async throws { throw Failure.unimplemented }
  func mergeBase(_ a: String, _ b: String) async throws -> ObjectID {
    guard let oid = mergeBases["\(a)...\(b)"] else { throw Failure.unimplemented }
    return oid
  }
  func diff(from: String, to: String) async throws -> [FileDiff] { [] }
  func diffText(from: String, to: String) async throws -> String { "" }
  func stagedDiffText() async throws -> String { "" }
  func saveStash(message: String?, includeUntracked: Bool) async throws {
    throw Failure.unimplemented
  }
  func applyStash(_ stash: Stash, pop: Bool) async throws { throw Failure.unimplemented }
  func dropStash(_ stash: Stash) async throws { throw Failure.unimplemented }
  func stashDiffs(_ stash: Stash) async throws -> [FileDiff] { [] }
}
