import Foundation
import Testing

@testable import SpoonCore

/// Live round-trips for the branch / worktree / stash-detail / sequencer
/// operations, against the real git CLI in throwaway repositories.
@Suite("LiveSequencer", .serialized)
struct LiveSequencerTests {
  private let runner = SubprocessCommandRunner()

  private func makeClient(_ root: URL) -> SystemGitClient {
    LiveRepoFixture.makeClient(for: root, runner: runner)
  }

  private func arrange(_ arguments: [String], in root: URL) async throws {
    try await LiveRepoFixture.run(arguments, in: root, runner: runner)
  }

  private func commitFile(
    _ file: String, _ content: String, message: String, in root: URL
  ) async throws {
    try await LiveRepoFixture.commitFile(
      file, content: content, message: message, in: root, runner: runner)
  }

  /// History: base (base.txt) → second (second.txt) → third (third.txt).
  private func makeThreeCommitRepo() async throws -> URL {
    try await LiveRepoFixture.makeTemporaryRepo(
      commits: ["base", "second", "third"].map {
        LiveRepoFixture.CommitSpec(file: "\($0).txt", content: "\($0)\n", message: $0)
      },
      runner: runner
    )
  }

  /// Oldest-first plan covering `commits.prefix(upToOldest)` … HEAD.
  private func plan(
    from commits: [Commit], oldest subject: String, actions: [String: RebaseAction]
  ) throws -> RebasePlan {
    let oldestIndex = try #require(commits.firstIndex { $0.subject == subject })
    let steps = commits[...oldestIndex].reversed().map { commit in
      RebaseStep(action: actions[commit.subject] ?? .pick, commit: commit)
    }
    return RebasePlan(steps: Array(steps), baseOID: commits[oldestIndex].parents.first)
  }

  // MARK: - Interactive rebase

  @Test func squashCombinesCommitsAndKeepsBothMessages() async throws {
    let root = try await makeThreeCommitRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)

    let commits = try await client.log(LogQuery()).commits
    let plan = try plan(from: commits, oldest: "second", actions: ["third": .squash])
    try await client.interactiveRebase(plan)

    let after = try await client.log(LogQuery()).commits
    #expect(after.map(\.subject) == ["second", "base"])
    let detail = try await client.commitDetail(after[0].oid)
    #expect(detail.fullMessage.contains("second"))
    #expect(detail.fullMessage.contains("third"))
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "third.txt").path))
    #expect(try await client.sequencerState() == nil)
  }

  @Test func rewordAndFixupRewriteHistory() async throws {
    let root = try await makeThreeCommitRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    let commits = try await client.log(LogQuery()).commits
    let second = try #require(commits.first { $0.subject == "second" })
    let third = try #require(commits.first { $0.subject == "third" })
    let plan = RebasePlan(
      steps: [
        RebaseStep(
          action: .reword,
          commit: second,
          newMessage: "renamed second\n\nreplacement body"
        ),
        RebaseStep(action: .fixup, commit: third),
      ],
      baseOID: second.parents.first
    )

    try await client.interactiveRebase(plan)

    let after = try await client.log(LogQuery())
    #expect(after.commits.map(\.subject) == ["renamed second", "base"])
    let detail = try await client.commitDetail(after.commits[0].oid)
    #expect(detail.fullMessage.contains("replacement body"))
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "third.txt").path))
  }

  @Test func dropRemovesCommitAndItsFile() async throws {
    let root = try await makeThreeCommitRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)

    let commits = try await client.log(LogQuery()).commits
    let plan = try plan(from: commits, oldest: "second", actions: ["second": .drop])
    try await client.interactiveRebase(plan)

    let after = try await client.log(LogQuery()).commits
    #expect(after.map(\.subject) == ["third", "base"])
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "second.txt").path))
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "third.txt").path))
  }

  @Test func editPausesTheRebaseAndContinueFinishesIt() async throws {
    let root = try await makeThreeCommitRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)

    let commits = try await client.log(LogQuery()).commits
    let plan = try plan(from: commits, oldest: "second", actions: ["second": .edit])
    try await client.interactiveRebase(plan)

    let paused = try #require(try await client.sequencerState())
    #expect(paused.kind == .rebase)
    #expect(paused.branchName == "main")
    #expect(paused.stoppedOID != nil)
    #expect(paused.stepNumber == 1)
    #expect(paused.stepCount == 2)
    // An edit pause is not a conflict.
    #expect(try await client.status().conflictedEntries.isEmpty)

    try await client.continueSequencer(.rebase)
    #expect(try await client.sequencerState() == nil)
    let after = try await client.log(LogQuery()).commits
    #expect(after.map(\.subject) == ["third", "second", "base"])
  }

  @Test func conflictIsDetectedAndAbortRestoresEverything() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    // Three commits rewriting the same line: dropping the middle one makes
    // the third one conflict.
    try await commitFile("file.txt", "one\n", message: "c1", in: root)
    try await commitFile("file.txt", "two\n", message: "c2", in: root)
    try await commitFile("file.txt", "three\n", message: "c3", in: root)
    let client = makeClient(root)

    let commits = try await client.log(LogQuery()).commits
    let plan = try plan(from: commits, oldest: "c2", actions: ["c2": .drop])
    await #expect(throws: CommandError.self) {
      try await client.interactiveRebase(plan)
    }

    let state = try #require(try await client.sequencerState())
    #expect(state.kind == .rebase)
    #expect(try await client.status().conflictedEntries.map(\.path) == ["file.txt"])

    try await client.abortSequencer(.rebase)
    #expect(try await client.sequencerState() == nil)
    #expect(try await client.log(LogQuery()).commits.map(\.subject) == ["c3", "c2", "c1"])
    #expect(try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "three\n")
  }

  // MARK: - Cherry-pick / revert

  @Test func cherryPickAppliesCommitFromAnotherBranch() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    try await arrange(["switch", "-c", "side"], in: root)
    try await commitFile("side.txt", "side\n", message: "side commit", in: root)
    try await arrange(["switch", "main"], in: root)
    let client = makeClient(root)

    let sideTip = try #require(
      try await client.log(LogQuery(reference: "side", maxCount: 1)).commits.first
    )
    try await client.cherryPick(sideTip.oid)

    let after = try await client.log(LogQuery()).commits
    #expect(after.map(\.subject) == ["side commit", "base"])
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "side.txt").path))
  }

  @Test func cherryPickConflictIsDetectedAndAbortable() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("file.txt", "one\n", message: "base", in: root)
    try await arrange(["switch", "-c", "side"], in: root)
    try await commitFile("file.txt", "side\n", message: "side edit", in: root)
    try await arrange(["switch", "main"], in: root)
    try await commitFile("file.txt", "main\n", message: "main edit", in: root)
    let client = makeClient(root)

    let sideTip = try #require(
      try await client.log(LogQuery(reference: "side", maxCount: 1)).commits.first
    )
    await #expect(throws: CommandError.self) {
      try await client.cherryPick(sideTip.oid)
    }
    #expect(try await client.sequencerState()?.kind == .cherryPick)

    try await client.abortSequencer(.cherryPick)
    #expect(try await client.sequencerState() == nil)
    #expect(try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "main\n")
  }

  @Test func revertAddsAnInverseCommit() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("file.txt", "one\n", message: "c1", in: root)
    try await commitFile("file.txt", "two\n", message: "c2", in: root)
    let client = makeClient(root)

    let head = try #require(try await client.log(LogQuery()).commits.first)
    try await client.revert(head.oid)

    let after = try await client.log(LogQuery()).commits
    #expect(after.count == 3)
    #expect(after[0].subject.hasPrefix("Revert"))
    #expect(try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "one\n")
  }

  @Test func reorderedRebasePlanSwapsCommitOrder() async throws {
    let root = try await makeThreeCommitRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)

    let commits = try await client.log(LogQuery()).commits
    let second = try #require(commits.first { $0.subject == "second" })
    let third = try #require(commits.first { $0.subject == "third" })
    // Reordered oldest-first todo: third applies before second.
    let plan = RebasePlan(
      steps: [RebaseStep(action: .pick, commit: third), RebaseStep(action: .pick, commit: second)],
      baseOID: second.parents.first
    )
    try await client.interactiveRebase(plan)

    let after = try await client.log(LogQuery()).commits
    #expect(after.map(\.subject) == ["second", "third", "base"])
  }

  // MARK: - Merge

  /// main and side diverge with independent files.
  private func makeDivergedRepo() async throws -> URL {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    try await arrange(["switch", "-c", "side"], in: root)
    try await commitFile("side.txt", "side\n", message: "side commit", in: root)
    try await arrange(["switch", "main"], in: root)
    try await commitFile("main.txt", "main\n", message: "main commit", in: root)
    return root
  }

  @Test func mergeCreatesAMergeCommit() async throws {
    let root = try await makeDivergedRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)

    try await client.merge(branch: "side", options: .standard)

    let head = try #require(try await client.log(LogQuery()).commits.first)
    #expect(head.isMerge)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "side.txt").path))
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "main.txt").path))
  }

  @Test func squashMergeStagesWithoutCommitting() async throws {
    let root = try await makeDivergedRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    let countBefore = try await client.log(LogQuery()).commits.count

    try await client.merge(
      branch: "side",
      options: MergeOptions(commitMode: .squash)
    )

    let status = try await client.status()
    #expect(status.stagedEntries.map(\.path) == ["side.txt"])
    #expect(try await client.log(LogQuery()).commits.count == countBefore)

    try await client.commit(message: "squash side", amend: false)
    let head = try #require(try await client.log(LogQuery()).commits.first)
    #expect(head.subject == "squash side")
    #expect(!head.isMerge)
  }

  @Test func fastForwardOnlyRefusesDivergedBranches() async throws {
    let root = try await makeDivergedRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    let headBefore = try #require(try await client.log(LogQuery()).commits.first?.oid)

    await #expect(throws: CommandError.self) {
      try await client.merge(
        branch: "side",
        options: MergeOptions(commitMode: .fastForwardOnly)
      )
    }

    #expect(try await client.log(LogQuery()).commits.first?.oid == headBefore)
    #expect(try await client.sequencerState() == nil)
  }

  @Test func mergeCanPreferTheirsForConflictingHunks() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("file.txt", "base\n", message: "base", in: root)
    try await arrange(["switch", "-c", "side"], in: root)
    try await commitFile("file.txt", "side\n", message: "side edit", in: root)
    try await arrange(["switch", "main"], in: root)
    try await commitFile("file.txt", "main\n", message: "main edit", in: root)
    let client = makeClient(root)

    try await client.merge(
      branch: "side",
      options: MergeOptions(strategy: .ort, conflictPreference: .theirs)
    )

    #expect(try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "side\n")
    #expect(try await client.status().conflictedEntries.isEmpty)
  }

  @Test func mergeConflictIsDetectedAndAbortable() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("file.txt", "one\n", message: "base", in: root)
    try await arrange(["switch", "-c", "side"], in: root)
    try await commitFile("file.txt", "side\n", message: "side edit", in: root)
    try await arrange(["switch", "main"], in: root)
    try await commitFile("file.txt", "main\n", message: "main edit", in: root)
    let client = makeClient(root)

    await #expect(throws: CommandError.self) {
      try await client.merge(branch: "side", options: .standard)
    }
    #expect(try await client.sequencerState()?.kind == .merge)
    #expect(try await client.status().conflictedEntries.map(\.path) == ["file.txt"])

    try await client.abortSequencer(.merge)
    #expect(try await client.sequencerState() == nil)
    #expect(try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "main\n")
  }

  // MARK: - Tags / revision switching

  @Test func tagLifecycleRoundTrip() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    let client = makeClient(root)
    let head = try #require(try await client.log(LogQuery()).commits.first)

    try await client.createTag(name: "light", at: nil, message: nil)
    try await client.createTag(name: "v1.0.0", at: head.oid, message: "first release")

    let tags = try await client.tags()
    #expect(Set(tags.map(\.name)) == ["light", "v1.0.0"])
    let annotated = try #require(tags.first { $0.name == "v1.0.0" })
    // The annotated tag peels to the tagged commit.
    #expect(annotated.target == head.oid)
    #expect(annotated.isAnnotated)
    let lightweight = try #require(tags.first { $0.name == "light" })
    #expect(lightweight.target == head.oid)
    #expect(!lightweight.isAnnotated)

    try await client.deleteTag(name: "light")
    #expect(try await client.tags().map(\.name) == ["v1.0.0"])
  }

  @Test func remoteTagPushAndDeleteRoundTrip() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    let origin = URL.temporaryDirectory.appending(path: "spoon-tag-origin-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: origin)
    }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    try await arrange(["init", "--bare", origin.path], in: root)
    try await arrange(["remote", "add", "origin", origin.path], in: root)
    let client = makeClient(root)
    let remoteClient = makeClient(origin)
    try await client.createTag(name: "v1", at: nil, message: nil)
    try await client.createTag(name: "v2", at: nil, message: nil)

    try await client.pushTag(name: "v1", to: "origin")
    #expect(try await remoteClient.tags().map(\.name) == ["v1"])

    try await client.pushAllTags(to: "origin")
    #expect(Set(try await remoteClient.tags().map(\.name)) == ["v1", "v2"])

    try await client.deleteRemoteTag(name: "v1", from: "origin")
    #expect(try await remoteClient.tags().map(\.name) == ["v2"])
    #expect(Set(try await client.tags().map(\.name)) == ["v1", "v2"])
  }

  @Test func switchToRevisionDetachesHead() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("file.txt", "one\n", message: "c1", in: root)
    try await commitFile("file.txt", "two\n", message: "c2", in: root)
    let client = makeClient(root)
    let first = try #require(try await client.log(LogQuery()).commits.last)

    try await client.switchToRevision(first.oid)

    let status = try await client.status()
    #expect(status.headBranch == nil)
    #expect(status.headOID == first.oid)
    #expect(try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "one\n")
  }

  // MARK: - Branches / worktrees

  @Test func deleteBranchRefusesUnmergedUnlessForced() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    let client = makeClient(root)

    try await client.createBranch(name: "merged", from: nil, switchToBranch: false)
    try await client.deleteBranch(name: "merged", force: false)

    try await arrange(["switch", "-c", "unmerged"], in: root)
    try await commitFile("extra.txt", "extra\n", message: "extra", in: root)
    try await arrange(["switch", "main"], in: root)
    await #expect(throws: CommandError.self) {
      try await client.deleteBranch(name: "unmerged", force: false)
    }
    try await client.deleteBranch(name: "unmerged", force: true)
    #expect(try await client.branches().map(\.name) == ["main"])
  }

  @Test func createBranchFromAnotherBranchStartsAtItsTip() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    try await arrange(["switch", "-c", "side"], in: root)
    try await commitFile("side.txt", "side\n", message: "side commit", in: root)
    try await arrange(["switch", "main"], in: root)
    let client = makeClient(root)

    // Without switching: HEAD stays on main, the copy points at side's tip.
    try await client.createBranch(name: "copy", from: "side", switchToBranch: false)
    let branches = try await client.branches()
    let side = try #require(branches.first { $0.name == "side" })
    let copy = try #require(branches.first { $0.name == "copy" })
    #expect(copy.tip == side.tip)
    #expect(try await client.status().headBranch == "main")

    // With switching: HEAD moves to the new branch.
    try await client.createBranch(name: "copy-switched", from: "side", switchToBranch: true)
    #expect(try await client.status().headBranch == "copy-switched")
  }

  @Test func switchToRemoteBranchCreatesTrackingLocalBranch() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    let origin = URL.temporaryDirectory.appending(path: "spoon-origin-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: origin)
    }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    try await arrange(["switch", "-c", "feature"], in: root)
    try await commitFile("feature.txt", "f\n", message: "feature commit", in: root)
    try await arrange(["switch", "main"], in: root)
    // Publish to a bare "remote", then drop the local feature branch.
    try await arrange(["init", "--bare", origin.path], in: root)
    try await arrange(["remote", "add", "origin", origin.path], in: root)
    try await arrange(["push", "origin", "main", "feature"], in: root)
    try await arrange(["branch", "-D", "feature"], in: root)
    let client = makeClient(root)

    try await client.switchToRemoteBranch("origin/feature")

    let status = try await client.status()
    #expect(status.headBranch == "feature")
    let feature = try #require(try await client.branches().first { $0.name == "feature" })
    #expect(feature.upstream == "origin/feature")
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "feature.txt").path))
  }

  @Test func renameBranchRenamesCurrentAndOtherBranches() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    let client = makeClient(root)

    try await client.createBranch(name: "feature", from: nil, switchToBranch: false)
    try await client.renameBranch(from: "feature", to: "feature/renamed")
    // Renaming the current branch works too.
    try await client.renameBranch(from: "main", to: "trunk")

    let names = try await client.branches().map(\.name).sorted()
    #expect(names == ["feature/renamed", "trunk"])
    #expect(try await client.status().headBranch == "trunk")
  }

  @Test func worktreeAddListRemoveRoundTrip() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    let worktreePath = URL.temporaryDirectory
      .appending(path: "spoon-worktree-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: worktreePath)
    }
    try await commitFile("base.txt", "base\n", message: "base", in: root)
    let client = makeClient(root)

    try await client.createBranch(name: "feature", from: nil, switchToBranch: false)
    try await client.addWorktree(path: worktreePath, branch: "feature")

    let worktrees = try await client.worktrees()
    #expect(worktrees.count == 2)
    #expect(worktrees[0].isMain)
    #expect(worktrees[0].branch == "main")
    #expect(worktrees[1].branch == "feature")
    #expect(worktrees[1].name == worktreePath.lastPathComponent)

    try await client.removeWorktree(path: worktreePath, force: false)
    #expect(try await client.worktrees().count == 1)
  }

  @Test func sparseCheckoutSetListAndDisableRoundTrip() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appending(path: "Sources"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: root.appending(path: "Tests"),
      withIntermediateDirectories: true
    )
    try Data("source\n".utf8).write(to: root.appending(path: "Sources/App.swift"))
    try Data("test\n".utf8).write(to: root.appending(path: "Tests/AppTests.swift"))
    try await arrange(["add", "."], in: root)
    try await arrange(["commit", "-m", "add tree"], in: root)
    let client = makeClient(root)

    try await client.setSparseCheckout(paths: ["Sources"])
    #expect(try await client.sparseCheckoutPaths() == ["Sources"])
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "Sources/App.swift").path))
    #expect(
      !FileManager.default.fileExists(atPath: root.appending(path: "Tests/AppTests.swift").path))

    try await client.disableSparseCheckout()
    #expect(try await client.sparseCheckoutPaths() == nil)
    #expect(
      FileManager.default.fileExists(atPath: root.appending(path: "Tests/AppTests.swift").path))
  }

  // MARK: - Stash detail / staged line unstage

  @Test func stashDiffsShowTrackedAndUntrackedChanges() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    try await commitFile("file.txt", "one\n", message: "base", in: root)
    let client = makeClient(root)

    try Data("two\n".utf8).write(to: root.appending(path: "file.txt"))
    try Data("new\n".utf8).write(to: root.appending(path: "brand-new.txt"))
    try await client.saveStash(message: "wip stash", includeUntracked: true)

    let stash = try #require(try await client.stashes().first)
    #expect(stash.message.contains("wip stash"))
    let diffs = try await client.stashDiffs(stash)
    #expect(diffs.map(\.path).sorted() == ["brand-new.txt", "file.txt"])
  }

  @Test func stagedLineUnstageRevertsOnlySelectedLinesInIndex() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    let numbers = (1...9).map(String.init)
    try await commitFile(
      "file.txt", numbers.joined(separator: "\n") + "\n", message: "base", in: root)

    var edited = numbers
    edited[3] = "FOUR"
    edited[5] = "SIX"
    try Data((edited.joined(separator: "\n") + "\n").utf8)
      .write(to: root.appending(path: "file.txt"))
    try await arrange(["add", "file.txt"], in: root)
    let client = makeClient(root)

    let staged = try #require(
      try await client.diffWorkingTree(path: "file.txt", staged: true).first)
    let hunk = try #require(staged.hunks.first)
    let fourOffsets = Set(
      hunk.lines.indices.filter { hunk.lines[$0].text == "4" || hunk.lines[$0].text == "FOUR" }
    )
    let patch = try #require(
      DiffPatchBuilder.discardPatch(for: staged, hunkID: hunk.id, selectedOffsets: fourOffsets)
    )
    try await client.applyPatch(patch, reverse: true, toIndex: true)

    // Index keeps only the SIX edit; the working tree still has both.
    let after = try #require(try await client.diffWorkingTree(path: "file.txt", staged: true).first)
    let changed = after.hunks.flatMap(\.lines).filter { $0.kind != .context }.map(\.text)
    #expect(changed.sorted() == ["6", "SIX"])
    let worktree = try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8)
    #expect(worktree.contains("FOUR") && worktree.contains("SIX"))
  }
}
