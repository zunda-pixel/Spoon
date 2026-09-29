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

  @Test func historyReferenceModesAreExclusiveAndSupportMultipleFocuses() async {
    let client = FakeRepositoryGitClient()
    let mainOID = makeOID("a1a1a1a1")
    let topicOID = makeOID("b2b2b2b2")
    await client.configure(
      status: makeStatus(oid: mainOID, branch: "main"),
      branches: [
        makeBranch("main", oid: mainOID, isCurrent: true),
        makeBranch("topic", oid: topicOID, isCurrent: false),
      ],
      logPages: [0: LogPage(commits: [], hasMore: false)]
    )
    let model = RepositoryModel(
      repository: Repository(rootURL: URL(filePath: "/tmp/history-filter-" + UUID().uuidString)),
      gitClient: client
    )
    await model.refresh()

    let mainID = HistoryReferenceFilterID.localBranch("main").id
    let topicID = HistoryReferenceFilterID.localBranch("topic").id
    await model.toggleHistoryFocus(mainID)
    await model.toggleHistoryFocus(topicID)

    #expect(model.focusedHistoryReferenceIDs == [mainID, topicID])
    #expect(model.hiddenHistoryReferenceIDs.isEmpty)

    await model.toggleHistoryHidden(mainID)

    #expect(model.focusedHistoryReferenceIDs.isEmpty)
    #expect(model.hiddenHistoryReferenceIDs == [mainID])

    await model.toggleHistoryHidden(mainID)
    #expect(model.hiddenHistoryReferenceIDs.isEmpty)
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

  @Test func onlyExistingRemoteUpstreamsAreOfferedForRenameOrDelete() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("27272727")
    let live = makeBranch("live", oid: oid, isCurrent: false, upstream: "origin/live")
    var gone = makeBranch("gone", oid: oid, isCurrent: false, upstream: "origin/gone")
    gone.upstreamGone = true
    let pruned = makeBranch("pruned", oid: oid, isCurrent: false, upstream: "origin/pruned")
    let local = makeBranch("stacked", oid: oid, isCurrent: false, upstream: "main")
    let untracked = makeBranch("untracked", oid: oid, isCurrent: false)
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [live, gone, pruned, local, untracked],
      remotes: [Remote(name: "origin", fetchURL: "https://example.com/r.git", pushURL: nil)],
      remoteBranchesByRemote: ["origin": [makeBranch("origin/live", oid: oid, isCurrent: false)]]
    )
    let model = makeModel(client)
    await model.refresh()

    #expect(model.existingRemoteUpstream(of: live) == "origin/live")
    #expect(model.existingRemoteUpstream(of: gone) == nil)
    #expect(model.existingRemoteUpstream(of: pruned) == nil)
    #expect(model.existingRemoteUpstream(of: local) == nil)
    #expect(model.existingRemoteUpstream(of: untracked) == nil)
  }

  @Test func bulkDeleteRemovesEachBranchAndItsRemoteInOrder() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("28282828")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [makeBranch("main", oid: oid, isCurrent: true)]
    )
    let model = makeModel(client)

    await model.deleteBranches([
      .init(name: "merged", force: false),
      .init(name: "unmerged", force: true, remoteUpstream: "origin/unmerged"),
    ])

    #expect(
      await client.mutationCalls == [
        "delete-local:merged:false",
        "delete-local:unmerged:true",
        "delete-remote:origin:unmerged",
      ]
    )
  }

  @Test func pullRequestPublishesBranchesWithoutLiveUpstream() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("26262627")
    var gone = makeBranch("gone", oid: oid, isCurrent: false, upstream: "fork/gone")
    gone.upstreamGone = true
    let local = makeBranch("local", oid: oid, isCurrent: true)
    let tracked = makeBranch("tracked", oid: oid, isCurrent: false, upstream: "origin/tracked")
    await client.configure(
      status: makeStatus(oid: oid, branch: "local"),
      branches: [gone, local, tracked],
      remotes: [
        Remote(name: "fork", fetchURL: "git@github.com:me/repo.git"),
        Remote(name: "origin", fetchURL: "git@github.com:org/repo.git"),
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    #expect(await model.publishBranchForPullRequest(local) == local)
    #expect(await model.publishBranchForPullRequest(gone) == gone)
    #expect(await model.publishBranchForPullRequest(tracked) == tracked)

    #expect(
      await client.mutationCalls == [
        "publish:origin:local",
        "publish:fork:gone",
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

  @Test func worktreeRemovalCanDeleteItsLocalAndRemoteBranchesInOrder() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("28282828")
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [
        makeBranch("main", oid: oid, isCurrent: true),
        makeBranch(
          "topic",
          oid: oid,
          isCurrent: false,
          upstream: "origin/topic"
        ),
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
      forceDeleteBranch: true,
      deleteRemoteUpstream: "origin/topic"
    )

    #expect(
      await client.mutationCalls == [
        "remove-worktree:\(firstPath.path):false",
        "remove-worktree:\(secondPath.path):true",
        "delete-local:topic:true",
        "delete-remote:origin:topic",
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
    let firstQuery = await client.logQueries.first
    #expect(firstQuery?.allReferences == true)
    #expect(firstQuery?.maxCount == 500)

    await model.loadMoreHistory()
    #expect(model.historyRows.map(\.commit.subject) == ["first", "second"])
    #expect(!model.hasMoreHistory)
  }

  @Test func historyHidesStashHelperCommitsAndSkipsEmptyVisiblePages() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("11111111")
    let stashOID = makeOID("22222222")
    let indexOID = makeOID("33333333")
    let stashCommit = Commit(
      oid: stashOID,
      parents: [head, indexOID],
      subject: "On main: work",
      authorName: "Tester",
      authorEmail: "tester@example.com",
      authoredAt: .distantPast,
      committedAt: .distantPast
    )
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      stashes: [
        Stash(
          index: 0,
          target: stashOID,
          helperCommitOIDs: [indexOID],
          message: "On main: work"
        )
      ],
      logPages: [
        0: LogPage(commits: [stashCommit], hasMore: true),
        500: LogPage(
          commits: [makeCommit("33333333", subject: "index on main")],
          hasMore: true
        ),
        1000: LogPage(commits: [makeCommit("11111111", subject: "base")], hasMore: false),
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.loadHistoryIfNeeded()
    await model.loadMoreHistory()

    #expect(model.historyRows.map(\.commit.oid) == [stashOID, head])
    #expect(model.historyRows.first?.commit.parents == [head])
    #expect(await client.logQueries.map(\.skip) == [0, 500, 1000])
  }

  @Test func revertIsAvailableOnlyForCommitsReachableFromCurrentHead() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    let otherBranch = makeOID("bbbb2222")
    let base = makeOID("cccc3333")
    func commit(_ oid: ObjectID, parent: ObjectID?, subject: String) -> Commit {
      Commit(
        oid: oid,
        parents: parent.map { [$0] } ?? [],
        subject: subject,
        authorName: "Tester",
        authorEmail: "tester@example.com",
        authoredAt: .distantPast,
        committedAt: .distantPast
      )
    }
    await client.configure(
      status: makeStatus(oid: head, branch: "A"),
      branches: [
        makeBranch("A", oid: head, isCurrent: true),
        makeBranch("B", oid: otherBranch, isCurrent: false),
      ],
      logPages: [
        0: LogPage(
          commits: [
            commit(head, parent: base, subject: "A change"),
            commit(otherBranch, parent: base, subject: "B change"),
            commit(base, parent: nil, subject: "base"),
          ],
          hasMore: false
        )
      ]
    )
    let model = makeModel(client)
    await model.refresh()
    await model.loadHistoryIfNeeded()

    #expect(model.canRevert(head))
    #expect(model.canRevert(base))
    #expect(!model.canRevert(otherBranch))
  }

  @Test func referenceCompatibilityLoadDoesNotReloadUnifiedHistory() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("45454545")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      logPages: [
        0: LogPage(
          commits: [makeCommit("45454545", subject: "tip")],
          hasMore: false
        )
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.loadHistoryIfNeeded()
    await model.loadHistoryIfNeeded(reference: "topic")

    #expect(await client.logQueries.count == 1)
    #expect(await client.logQueries.first?.allReferences == true)
  }

  @Test func emptyRepositoryDoesNotAttemptHistoryWalk() async {
    let client = FakeRepositoryGitClient()
    await client.configure(
      status: WorkingTreeStatus(headOID: nil, headBranch: "main"),
      branches: []
    )
    let model = makeModel(client)
    await model.refresh()

    await model.loadHistoryIfNeeded()

    #expect(model.historyRows.isEmpty)
    #expect(!model.hasMoreHistory)
    #expect(await client.logQueries.isEmpty)
  }

  @Test func historyDoesNotLoadDetachedWorktreeHeadsAcrossPages() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("77777777")
    let detached = makeOID("88889999")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      worktrees: [
        Worktree(
          path: URL(filePath: "/tmp/main"),
          branch: "main",
          headOID: head,
          isMain: true
        ),
        Worktree(
          path: URL(filePath: "/tmp/detached-one"),
          branch: nil,
          headOID: detached,
          isMain: false
        ),
        Worktree(
          path: URL(filePath: "/tmp/detached-two"),
          branch: nil,
          headOID: detached,
          isMain: false
        ),
      ],
      logPages: [
        0: LogPage(commits: [makeCommit("77777777", subject: "feature")], hasMore: true),
        500: LogPage(commits: [], hasMore: false),
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.loadHistoryIfNeeded(reference: "feature/topic")
    await model.loadMoreHistory()

    let queries = await client.logQueries
    #expect(queries.map(\.reference) == [nil, nil])
    #expect(queries.map(\.allReferences) == [true, true])
    #expect(queries.map(\.additionalRevisions) == [[], []])
  }

  @Test func ensureCommitLoadedPagesUntilTheRequestedOIDAppears() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("91919191")
    let requested = makeOID("93939393")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      logPages: [
        0: LogPage(
          commits: [makeCommit("91919191", subject: "first page")],
          hasMore: true
        ),
        500: LogPage(
          commits: [makeCommit("92929292", subject: "second page")],
          hasMore: true
        ),
        1000: LogPage(
          commits: [makeCommit("93939393", subject: "requested")],
          hasMore: false
        ),
      ]
    )
    let model = makeModel(client)
    await model.refresh()
    await model.loadHistoryIfNeeded()

    #expect(await model.ensureCommitLoaded(requested))
    #expect(
      model.historyRows.map(\.commit.oid) == [
        makeOID("91919191"),
        makeOID("92929292"),
        requested,
      ]
    )
    #expect(await client.logQueries.map(\.skip) == [0, 500, 1000])
  }

  @Test func ensureCommitLoadedWaitsForBackgroundPagination() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("a1a1a1a1")
    let requested = makeOID("c3c3c3c3")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      logPages: [
        0: LogPage(
          commits: [makeCommit("a1a1a1a1", subject: "first page")],
          hasMore: true
        ),
        500: LogPage(
          commits: [makeCommit("b2b2b2b2", subject: "background page")],
          hasMore: true
        ),
        1000: LogPage(
          commits: [makeCommit("c3c3c3c3", subject: "requested")],
          hasMore: false
        ),
      ],
      logDelays: [500: .milliseconds(100)]
    )
    let model = makeModel(client)
    await model.refresh()
    await model.loadHistoryIfNeeded()

    let backgroundLoad = Task { await model.loadMoreHistory() }
    while await client.logQueries.count < 2 {
      await Task.yield()
    }

    #expect(await model.ensureCommitLoaded(requested))
    await backgroundLoad.value
    #expect(await client.logQueries.map(\.skip) == [0, 500, 1000])
  }

  @Test func ensureCommitLoadedReturnsFalseAtTheEndOfHistory() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("94949494")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      logPages: [
        0: LogPage(
          commits: [makeCommit("94949494", subject: "first page")],
          hasMore: true
        ),
        500: LogPage(
          commits: [makeCommit("95959595", subject: "last page")],
          hasMore: false
        ),
      ]
    )
    let model = makeModel(client)
    await model.refresh()
    await model.loadHistoryIfNeeded()

    let found = await model.ensureCommitLoaded(makeOID("96969696"))
    #expect(!found)
    #expect(!model.hasMoreHistory)
    #expect(await client.logQueries.map(\.skip) == [0, 500])
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

  @Test func refreshContinuesUsingTheUnifiedHistoryQuery() async {
    let client = FakeRepositoryGitClient()
    let oid = makeOID("aaaaaaaa")
    let detached = makeOID("bbbbbbbb")
    let page = LogPage(commits: [makeCommit("aaaaaaaa", subject: "tip")], hasMore: false)
    await client.configure(
      status: makeStatus(oid: oid, branch: "main"),
      branches: [
        makeBranch("main", oid: oid, isCurrent: true),
        makeBranch("topic", oid: oid, isCurrent: false),
      ],
      worktrees: [
        Worktree(
          path: URL(filePath: "/tmp/detached"),
          branch: nil,
          headOID: detached,
          isMain: false
        )
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
      worktrees: [
        Worktree(
          path: URL(filePath: "/tmp/detached"),
          branch: nil,
          headOID: detached,
          isMain: false
        )
      ],
      logPages: [0: page]
    )
    await model.refreshGitState()

    let queries = await client.logQueries
    #expect(queries.map(\.reference) == [nil, nil])
    #expect(queries.map(\.allReferences) == [true, true])
    #expect(queries.map(\.additionalRevisions) == [[], []])
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

  @Test func dropCommitRequiresGit256AndASingleParent() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    let parent = makeOID("bbbb2222")
    var commit = makeCommit("aaaa1111", subject: "change")
    commit.parents = [parent]
    var root = makeCommit("bbbb2222", subject: "root")
    root.parents = []
    var merge = makeCommit("cccc3333", subject: "merge")
    merge.parents = [parent, head]
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      gitVersion: GitVersion(2, 55, 0)
    )
    let model = makeModel(client)
    await model.refresh()
    #expect(!model.canDropCommit(commit))

    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      gitVersion: GitVersion(2, 56, 0)
    )
    await model.refresh()
    #expect(model.canDropCommit(commit))
    #expect(!model.canDropCommit(root))
    #expect(!model.canDropCommit(merge))

    #expect(await model.dropCommit(head))
    #expect(await client.mutationCalls == ["drop:aaaa1111:false"])
  }

  @Test func deleteMergedBranchesDeletesOnlyThePreviewedNames() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)]
    )
    let model = makeModel(client)

    let preview = (try? await model.mergedBranchesToDelete()) ?? []
    await model.deleteMergedBranches(preview)
    await model.deleteMergedBranches([])

    #expect(preview == ["merged"])
    #expect(await client.mutationCalls == ["delete-merged::true", "delete-merged:merged:false"])
  }

  @Test func forkedBranchFocusShowsTheBaseAndItsForks() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [
        makeBranch("main", oid: head, isCurrent: true, upstream: "origin/main"),
        makeBranch("feature", oid: head, isCurrent: false, upstream: "origin/main"),
        makeBranch("other", oid: head, isCurrent: false, upstream: "origin/other"),
      ],
      remoteBranchesByRemote: [
        "origin": [makeBranch("origin/main", oid: head, isCurrent: false)]
      ]
    )
    let model = RepositoryModel(
      repository: Repository(rootURL: URL(filePath: "/tmp/forked-focus-" + UUID().uuidString)),
      gitClient: client
    )
    await model.refresh()

    await model.focusHistoryOnBranches(
      forkedFrom: .remoteBranch(remote: "origin", name: "origin/main")
    )

    #expect(
      model.focusedHistoryReferenceIDs
        == ["remote:origin:origin/main", "local:main", "local:feature"]
    )
  }

  @Test func onlyBranchesThatAreNotCheckedOutCanMove() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    let other = makeOID("bbbb2222")
    let target = makeOID("cccc3333")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [
        makeBranch("main", oid: head, isCurrent: true),
        makeBranch("topic", oid: other, isCurrent: false),
        makeBranch("in-worktree", oid: other, isCurrent: false),
        makeBranch("already-there", oid: target, isCurrent: false),
      ],
      worktrees: [
        Worktree(
          path: URL(filePath: "/tmp/in-worktree"),
          branch: "in-worktree",
          headOID: other,
          isMain: false
        )
      ]
    )
    let model = makeModel(client)
    await model.refresh()

    let movable = model.branchesMovable(to: target)
    #expect(movable.map(\.name) == ["topic"])

    await model.moveBranch(movable[0], to: target)
    #expect(await client.mutationCalls == ["move:topic:bbbb2222->cccc3333"])
  }

  @Test func replayRequiresGit256AndABranchThatIsNotCheckedOut() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    let topic = makeBranch("topic", oid: makeOID("bbbb2222"), isCurrent: false)
    let main = makeBranch("main", oid: head, isCurrent: true)
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [main, topic],
      gitVersion: GitVersion(2, 55, 0)
    )
    let model = makeModel(client)
    await model.refresh()
    #expect(!model.canReplayBranchOntoHead(topic))

    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [main, topic],
      gitVersion: GitVersion(2, 56, 0)
    )
    await model.refresh()
    #expect(model.canReplayBranchOntoHead(topic))
    #expect(!model.canReplayBranchOntoHead(main))

    #expect(await model.replayBranchOntoHead(topic, linearize: true))
    #expect(await client.mutationCalls == ["replay:topic:aaaa1111:true"])
  }

  @Test func largeBlobRemovalNeedsAPartialCloneOnGit256() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      gitVersion: GitVersion(2, 56, 0)
    )
    let model = makeModel(client)
    await model.refresh()
    #expect(!model.canDropLargeBlobs)

    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)],
      gitVersion: GitVersion(2, 56, 0),
      partialCloneRemote: "origin"
    )
    await model.refresh()
    #expect(model.canDropLargeBlobs)
    #expect(model.partialCloneRemote == "origin")

    await model.dropLargeBlobs(largerThan: 10)
    #expect(await client.mutationCalls == ["drop-blobs:10"])
  }

  @Test func backfillEstimateFallsBackToACountWhenSizesAreUnavailable() async throws {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    let missing = [makeOID("bbbb2222"), makeOID("cccc3333")]
    func configure(remoteObjectSize: Int?) async {
      await client.configure(
        status: makeStatus(oid: head, branch: "main"),
        branches: [makeBranch("main", oid: head, isCurrent: true)],
        gitVersion: GitVersion(2, 56, 0),
        partialCloneRemote: "origin",
        missingObjects: missing,
        remoteObjectSize: remoteObjectSize
      )
    }
    let model = makeModel(client)

    await configure(remoteObjectSize: 100)
    await model.refresh()
    #expect(model.canEstimateBackfill)
    let sized = try await model.backfillEstimate()
    #expect(sized.missingObjectCount == 2)
    #expect(sized.downloadByteCount == 200)

    await configure(remoteObjectSize: nil)
    let unsized = try await model.backfillEstimate()
    #expect(unsized.missingObjectCount == 2)
    #expect(unsized.downloadByteCount == nil)
    #expect(unsized.sizeUnavailableReason != nil)
  }

  @Test func stagingConflictedPathsMarksThemResolved() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    var status = makeStatus(oid: head, branch: "main")
    status.entries = [
      FileStatusEntry(path: "conflicted.txt", conflict: .bothModified),
      FileStatusEntry(path: "deleted-by-them.txt", conflict: .deletedByThem),
      FileStatusEntry(path: "edited.txt", unstaged: .modified),
    ]
    await client.configure(
      status: status,
      branches: [makeBranch("main", oid: head, isCurrent: true)]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.stage(paths: ["edited.txt", "conflicted.txt"])
    await model.resolveConflict(status.entries[0], using: .theirs)
    await model.resolveConflict(status.entries[1], using: .theirs)

    #expect(await client.stageCallCount == 1)
    #expect(
      await client.mutationCalls == [
        "resolved:conflicted.txt",
        "take:conflicted.txt:theirs:true",
        "take:deleted-by-them.txt:theirs:false",
      ]
    )
  }

  @Test func rewordAndFixupAreGatedOnGitVersionAndStagedChanges() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    var commit = makeCommit("aaaa1111", subject: "change")
    commit.parents = [makeOID("bbbb2222")]
    var staged = makeStatus(oid: head, branch: "main")
    staged.entries = [FileStatusEntry(path: "a.txt", staged: .modified)]
    let branches = [makeBranch("main", oid: head, isCurrent: true)]
    let model = makeModel(client)

    await client.configure(status: staged, branches: branches, gitVersion: GitVersion(2, 53, 0))
    await model.refresh()
    #expect(!model.canRewordCommit(commit))
    #expect(!model.canFixupCommit(commit))

    await client.configure(status: staged, branches: branches, gitVersion: GitVersion(2, 54, 0))
    await model.refresh()
    #expect(model.canRewordCommit(commit))
    #expect(!model.canFixupCommit(commit))

    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: branches,
      gitVersion: GitVersion(2, 55, 0)
    )
    await model.refresh()
    #expect(!model.canFixupCommit(commit))

    await client.configure(status: staged, branches: branches, gitVersion: GitVersion(2, 55, 0))
    await model.refresh()
    #expect(model.canFixupCommit(commit))

    await model.rewordCommit(head, message: "Better\n")
    await model.fixupCommit(head)
    #expect(await client.mutationCalls == ["reword:aaaa1111:Better\n", "fixup:aaaa1111:false"])
  }

  @Test func bisectRecordsTheCulpritAndStartsFromHead() async {
    let client = FakeRepositoryGitClient()
    let head = makeOID("aaaa1111")
    let good = makeOID("bbbb2222")
    let culprit = makeOID("cccc3333")
    await client.configure(
      status: makeStatus(oid: head, branch: "main"),
      branches: [makeBranch("main", oid: head, isCurrent: true)]
    )
    let model = makeModel(client)
    await model.refresh()

    await model.startBisect(good: good)
    #expect(model.bisectResult == nil)
    await client.setNextBisectProgress(.found(culprit))
    await model.markBisect(.bad)

    #expect(model.bisectResult == culprit)
    #expect(
      await client.mutationCalls == ["bisect-start:aaaa1111:bbbb2222", "bisect-bad:HEAD"]
    )
    model.dismissBisectResult()
    #expect(model.bisectResult == nil)
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
  private var currentCapabilities = GitCapabilities()
  private var currentBisectState: BisectState?
  private var nextBisectProgress = BisectProgress.testing(nil)
  private var currentPartialCloneRemote: String?
  private var currentMissingObjects: [ObjectID] = []
  private var currentRemoteObjectSize: Int?
  private var currentBranches: [Branch] = []
  private var currentRemotes: [Remote] = []
  private var currentRemoteBranchesByRemote: [String: [Branch]] = [:]
  private var currentStashes: [Stash] = []
  private var currentWorktrees: [Worktree] = []
  private var pages: [Int: LogPage] = [:]
  private var logDelays: [Int: Duration] = [:]
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
    stashes: [Stash] = [],
    worktrees: [Worktree] = [],
    logPages: [Int: LogPage] = [:],
    logDelays: [Int: Duration] = [:],
    mergeBases: [String: ObjectID] = [:],
    failBranches: Bool = false,
    failRemoteBranches: Bool = false,
    failWorktreeMutations: Bool = false,
    gitVersion: GitVersion? = nil,
    partialCloneRemote: String? = nil,
    missingObjects: [ObjectID] = [],
    remoteObjectSize: Int? = nil
  ) {
    currentStatus = status
    currentMissingObjects = missingObjects
    currentRemoteObjectSize = remoteObjectSize
    currentPartialCloneRemote = partialCloneRemote
    currentCapabilities = GitCapabilities(version: gitVersion)
    currentBranches = branches
    currentRemotes = remotes
    currentRemoteBranchesByRemote = remoteBranchesByRemote
    currentStashes = stashes
    currentWorktrees = worktrees
    pages = logPages
    self.logDelays = logDelays
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
  func stashes() async throws -> [Stash] { currentStashes }
  func tags() async throws -> [SpoonCore.Tag] { [] }
  func worktrees() async throws -> [Worktree] { currentWorktrees }
  func sequencerState() async throws -> SequencerState? { nil }
  func capabilities() async -> GitCapabilities { currentCapabilities }
  func repositoryPaths() async throws -> GitRepositoryPaths {
    let dotGit = repositoryRoot.appending(path: ".git", directoryHint: .isDirectory)
    return GitRepositoryPaths(gitDirectory: dotGit, commonDirectory: dotGit)
  }

  func markResolved(paths: [String]) async throws {
    mutationCalls.append("resolved:\(paths.joined(separator: ","))")
  }
  func resolveConflict(
    path: String,
    using side: FileStatusEntry.ConflictSide,
    sideHasFile: Bool
  ) async throws {
    mutationCalls.append("take:\(path):\(side.rawValue):\(sideHasFile)")
  }
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
    if let delay = logDelays[query.skip] {
      try await Task.sleep(for: delay)
    }
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
  func blame(path: String, at revision: ObjectID?) async throws -> [BlameLine] { [] }
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
  func mergePreview(branch: String) async throws -> MergePreview {
    MergePreview(conflictedPaths: [])
  }
  func deleteBranch(name: String, force: Bool) async throws {
    mutationCalls.append("delete-local:\(name):\(force)")
  }
  func deleteMergedBranches(branches: [String], dryRun: Bool) async throws -> [String] {
    mutationCalls.append("delete-merged:\(branches.joined(separator: ",")):\(dryRun)")
    return dryRun ? ["merged"] : branches
  }
  func moveBranch(name: String, to target: ObjectID, expectedTip: ObjectID) async throws {
    mutationCalls.append("move:\(name):\(expectedTip.rawValue)->\(target.rawValue)")
  }
  func renameBranch(from oldName: String, to newName: String) async throws {
    mutationCalls.append("rename-local:\(oldName):\(newName)")
  }
  func setUpstream(of branch: String, to upstream: String) async throws {
    mutationCalls.append("upstream:\(branch):\(upstream)")
  }
  func branchNames(forkedFrom upstream: String) async throws -> [String] {
    currentBranches.filter { "refs/remotes/\($0.upstream ?? "")" == upstream }.map(\.name)
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
  func publishBranch(_ branch: String, to remoteName: String) async throws {
    mutationCalls.append("publish:\(remoteName):\(branch)")
  }
  func fetch() async throws { throw Failure.unimplemented }
  func backfill() async throws { throw Failure.unimplemented }
  func partialCloneRemote() async throws -> String? { currentPartialCloneRemote }
  func missingObjectIDs() async throws -> [ObjectID] { currentMissingObjects }
  func remoteObjectSizes(of objects: [ObjectID], from remoteName: String) async throws
    -> [ObjectID: Int]
  {
    guard let currentRemoteObjectSize else { throw Failure.unimplemented }
    return Dictionary(uniqueKeysWithValues: objects.map { ($0, currentRemoteObjectSize) })
  }
  func dropLargeBlobs(largerThan byteLimit: Int) async throws {
    mutationCalls.append("drop-blobs:\(byteLimit)")
  }
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
  func replayBranch(_ branch: String, onto newBase: ObjectID, linearize: Bool) async throws {
    mutationCalls.append("replay:\(branch):\(newBase.rawValue):\(linearize)")
  }
  func rewordCommit(_ oid: ObjectID, message: String) async throws {
    mutationCalls.append("reword:\(oid.rawValue):\(message)")
  }
  func fixupCommit(_ oid: ObjectID, dryRun: Bool) async throws -> [RefUpdate] {
    mutationCalls.append("fixup:\(oid.rawValue):\(dryRun)")
    return []
  }
  func dropCommit(_ oid: ObjectID, dryRun: Bool) async throws -> [RefUpdate] {
    mutationCalls.append("drop:\(oid.rawValue):\(dryRun)")
    return []
  }
  func continueSequencer(_ kind: SequencerState.Kind) async throws { throw Failure.unimplemented }
  func skipSequencer(_ kind: SequencerState.Kind) async throws { throw Failure.unimplemented }
  func abortSequencer(_ kind: SequencerState.Kind) async throws { throw Failure.unimplemented }
  func bisectState() async throws -> BisectState? { currentBisectState }
  func startBisect(bad: ObjectID, good: ObjectID) async throws -> BisectProgress {
    mutationCalls.append("bisect-start:\(bad.rawValue):\(good.rawValue)")
    return nextBisectProgress
  }
  func markBisect(_ mark: BisectMark, revision: ObjectID?) async throws -> BisectProgress {
    mutationCalls.append("bisect-\(mark.rawValue):\(revision?.rawValue ?? "HEAD")")
    return nextBisectProgress
  }
  func resetBisect() async throws { mutationCalls.append("bisect-reset") }
  func setNextBisectProgress(_ progress: BisectProgress) { nextBisectProgress = progress }
  func mergeBase(_ a: String, _ b: String) async throws -> ObjectID {
    guard let oid = mergeBases["\(a)...\(b)"] else { throw Failure.unimplemented }
    return oid
  }
  func diff(from: String, to: String) async throws -> [FileDiff] { [] }
  func diffText(from: String, to: String) async throws -> String { "" }
  func stagedDiffText() async throws -> String { "" }
  func saveStash(_ options: StashSaveOptions) async throws {
    throw Failure.unimplemented
  }
  func applyStash(_ stash: Stash, pop: Bool) async throws { throw Failure.unimplemented }
  func dropStash(_ stash: Stash) async throws { throw Failure.unimplemented }
  func stashDiffs(_ stash: Stash) async throws -> [FileDiff] { [] }
}
