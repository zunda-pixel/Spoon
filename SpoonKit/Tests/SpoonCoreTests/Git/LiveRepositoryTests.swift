import Foundation
import Testing

@testable import SpoonCore

@Suite("Live Repository Operations", .serialized)
struct LiveRepositoryTests {
  private let runner = SubprocessCommandRunner()

  private func makeClient(_ root: URL) -> SystemGitClient {
    LiveRepoFixture.makeClient(for: root, runner: runner)
  }

  @Test func repositoryPathsLocateLinkedWorktreeMetadata() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    let linked = URL.temporaryDirectory.appending(path: "spoon-linked-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: linked)
    }
    try await LiveRepoFixture.run(
      ["worktree", "add", "-b", "linked", linked.path], in: root, runner: runner
    )

    let main = try await makeClient(root).repositoryPaths()
    let worktree = try await makeClient(linked).repositoryPaths()

    func canonical(_ url: URL) -> String {
      url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    let commonDirectory = canonical(main.commonDirectory)
    #expect(canonical(main.gitDirectory) == commonDirectory)
    #expect(canonical(worktree.commonDirectory) == commonDirectory)
    #expect(
      canonical(worktree.gitDirectory)
        == "\(commonDirectory)/worktrees/\(linked.lastPathComponent)"
    )
  }

  @Test func forkedBranchesMatchTheirConfiguredUpstream() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    for arguments in [
      ["branch", "--track", "forked", "main"],
      ["branch", "unrelated"],
    ] {
      try await LiveRepoFixture.run(arguments, in: root, runner: runner)
    }

    let names = try await makeClient(root).branchNames(forkedFrom: "refs/heads/main")

    #expect(names == ["forked"])
  }

  @Test func moveBranchRefusesAStaleExpectedTip() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "a.txt", content: "a\n", message: "first"),
        .init(file: "b.txt", content: "b\n", message: "second"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.run(["branch", "topic"], in: root, runner: runner)
    let client = makeClient(root)
    let commits = try await client.log(LogQuery(reference: "main", maxCount: 2)).commits
    let (second, first) = (commits[0].oid, commits[1].oid)

    await #expect(throws: CommandError.self) {
      try await client.moveBranch(name: "topic", to: first, expectedTip: first)
    }
    try await client.moveBranch(name: "topic", to: first, expectedTip: second)

    let topic = try await client.branches().first { $0.name == "topic" }
    #expect(topic?.tip == first)
  }

  @Test func partialCloneRemoteIsNilUntilConfigured() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)

    #expect(try await client.partialCloneRemote() == nil)
    try await LiveRepoFixture.run(
      ["config", "extensions.partialClone", "origin"], in: root, runner: runner
    )
    #expect(try await client.partialCloneRemote() == "origin")
  }

  @Test func fileHistoryCanFollowRenames() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "old.txt", content: "one\n", message: "add old")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.run(["mv", "old.txt", "new.txt"], in: root, runner: runner)
    try await LiveRepoFixture.run(["commit", "-m", "rename"], in: root, runner: runner)
    let client = makeClient(root)

    let plain = try await client.log(LogQuery(path: "new.txt"))
    let followed = try await client.log(LogQuery(path: "new.txt", followRenames: true))

    #expect(plain.commits.map(\.subject) == ["rename"])
    #expect(followed.commits.map(\.subject) == ["rename", "add old"])
  }

  @Test func mergePreviewFindsConflictsWithoutTouchingTheWorktree() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "shared.txt", content: "base\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.run(["branch", "topic"], in: root, runner: runner)
    try await LiveRepoFixture.run(["branch", "clean"], in: root, runner: runner)
    try await LiveRepoFixture.commitFile(
      "shared.txt", content: "main\n", message: "main edit", in: root, runner: runner
    )
    try await LiveRepoFixture.run(["switch", "topic"], in: root, runner: runner)
    try await LiveRepoFixture.commitFile(
      "shared.txt", content: "topic\n", message: "topic edit", in: root, runner: runner
    )
    try await LiveRepoFixture.run(["switch", "clean"], in: root, runner: runner)
    try await LiveRepoFixture.commitFile(
      "other.txt", content: "other\n", message: "other", in: root, runner: runner
    )
    try await LiveRepoFixture.run(["switch", "main"], in: root, runner: runner)
    let client = makeClient(root)

    let conflicted = try await client.mergePreview(branch: "topic")
    let clean = try await client.mergePreview(branch: "clean")

    #expect(conflicted.conflictedPaths == ["shared.txt"])
    #expect(clean.isClean)
    #expect(try await client.status().entries.isEmpty)
  }

  @Test func conflictsResolveToEitherSideOrADeletion() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "shared.txt", content: "base\n", message: "base"),
        .init(file: "doomed.txt", content: "base\n", message: "doomed"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    func git(_ arguments: [String]) async throws {
      try await LiveRepoFixture.run(arguments, in: root, runner: runner)
    }
    try await git(["switch", "-c", "topic"])
    try await LiveRepoFixture.commitFile(
      "shared.txt", content: "topic\n", message: "topic edit", in: root, runner: runner
    )
    try await git(["rm", "-q", "doomed.txt"])
    try await git(["commit", "-m", "delete doomed"])
    try await git(["switch", "main"])
    try await LiveRepoFixture.commitFile(
      "shared.txt", content: "main\n", message: "main edit", in: root, runner: runner
    )
    try await LiveRepoFixture.commitFile(
      "doomed.txt", content: "main\n", message: "main keeps doomed", in: root, runner: runner
    )
    let client = makeClient(root)
    await #expect(throws: CommandError.self) {
      try await client.merge(branch: "topic", options: .standard)
    }

    let conflicts = try await client.status().conflictedEntries
    let shared = try #require(conflicts.first { $0.path == "shared.txt" })
    let doomed = try #require(conflicts.first { $0.path == "doomed.txt" })
    try await client.resolveConflict(
      path: shared.path, using: .theirs, sideHasFile: shared.conflictSideHasFile(.theirs)
    )
    try await client.resolveConflict(
      path: doomed.path, using: .theirs, sideHasFile: doomed.conflictSideHasFile(.theirs)
    )

    let status = try await client.status()
    #expect(status.conflictedEntries.isEmpty)
    let merged = try String(contentsOf: root.appending(path: "shared.txt"), encoding: .utf8)
    #expect(merged == "topic\n")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "doomed.txt").path))
  }

  @Test func rewordReplacesAnOlderMessageWithoutTouchingTheWorktree() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "a.txt", content: "a\n", message: "frist"),
        .init(file: "b.txt", content: "b\n", message: "second"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("dirty\n".utf8).write(to: root.appending(path: "b.txt"))
    let client = makeClient(root)
    let first = try await client.log(LogQuery(maxCount: 2)).commits[1]

    try await client.rewordCommit(first.oid, message: "first\n\nFix the typo.\n")

    let commits = try await client.log(LogQuery(maxCount: 2)).commits
    #expect(commits.map(\.subject) == ["second", "first"])
    let detail = try await client.commitDetail(commits[1].oid)
    #expect(detail.fullMessage.contains("Fix the typo."))
    #expect(try await client.status().unstagedEntries.map(\.path) == ["b.txt"])
  }

  @Test func commitDetailReportsSshSignatureVerification() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    let keyDirectory = URL.temporaryDirectory.appending(path: "spoon-key-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: keyDirectory)
    }
    try FileManager.default.createDirectory(at: keyDirectory, withIntermediateDirectories: true)
    let key = keyDirectory.appending(path: "id_ed25519")
    let keygen = Command(
      executable: URL(filePath: "/usr/bin/ssh-keygen"),
      arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "spoon", "-f", key.path],
      workingDirectory: keyDirectory
    )
    _ = try await runner.run(keygen).checkSuccess(of: keygen)
    let publicKey = try String(contentsOf: key.appendingPathExtension("pub"), encoding: .utf8)
    let allowedSigners = keyDirectory.appending(path: "allowed_signers")
    try Data("test@example.com \(publicKey)".utf8).write(to: allowedSigners)
    for arguments in [
      ["config", "gpg.format", "ssh"],
      ["config", "user.signingkey", key.path],
      ["config", "gpg.ssh.allowedSignersFile", allowedSigners.path],
    ] {
      try await LiveRepoFixture.run(arguments, in: root, runner: runner)
    }
    try await LiveRepoFixture.commitFile(
      "unsigned.txt", content: "a\n", message: "unsigned", in: root, runner: runner
    )
    try Data("b\n".utf8).write(to: root.appending(path: "signed.txt"))
    try await LiveRepoFixture.run(["add", "signed.txt"], in: root, runner: runner)
    try await LiveRepoFixture.run(["commit", "-S", "-m", "signed"], in: root, runner: runner)
    let client = makeClient(root)
    let commits = try await client.log(LogQuery(maxCount: 2)).commits

    let signed = try await client.commitDetail(commits[0].oid)
    let unsigned = try await client.commitDetail(commits[1].oid)

    #expect(signed.signature?.status == .good)
    #expect(signed.signature?.signer == "test@example.com")
    #expect(unsigned.signature == nil)
  }

  @Test func partialStashesSaveOnlyTheRequestedChanges() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "a.txt", content: "a\n", message: "a"),
        .init(file: "b.txt", content: "b\n", message: "b"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    func write(_ file: String, _ text: String) throws {
      try Data(text.utf8).write(to: root.appending(path: file))
    }

    try write("a.txt", "a2\n")
    try write("b.txt", "b2\n")
    try await client.saveStash(StashSaveOptions(message: "only a", paths: ["a.txt"]))
    #expect(try await client.status().unstagedEntries.map(\.path) == ["b.txt"])

    try await client.stage(paths: ["b.txt"])
    try write("new.txt", "new\n")
    try await client.saveStash(StashSaveOptions(scope: .stagedOnly))
    let afterStaged = try await client.status()
    #expect(afterStaged.stagedEntries.isEmpty)
    #expect(afterStaged.untrackedEntries.map(\.path) == ["new.txt"])

    let stashes = try await client.stashes()
    #expect(stashes.count == 2)
    #expect(stashes[1].message.contains("only a"))
    let stagedStash = try await client.stashDiffs(stashes[0])
    #expect(stagedStash.map(\.path) == ["b.txt"])
  }

  @Test func cloneCreatesAWorkingLocalCopy() async throws {
    let source = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    let destination = URL.temporaryDirectory.appending(path: "spoon-clone-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }

    try await SystemGitClient.clone(
      from: source.path, to: destination, git: LiveRepoFixture.git, runner: runner
    ) { _ in }

    #expect(FileManager.default.fileExists(atPath: destination.appending(path: "base.txt").path))
    let root = await SystemGitClient.repositoryRoot(
      containing: destination, git: LiveRepoFixture.git, runner: runner)
    #expect(root != nil)
    let clone = makeClient(destination)
    #expect(try await clone.remotes().map(\.name) == ["origin"])
    #expect(try await clone.log(LogQuery()).commits.map(\.subject) == ["base"])
  }

  @Test func shallowSingleBranchCloneFetchesOnlyRequestedBranch() async throws {
    let source = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    let destination = URL.temporaryDirectory
      .appending(path: "spoon-shallow-clone-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }
    try await LiveRepoFixture.run(["switch", "-c", "side"], in: source, runner: runner)
    try await LiveRepoFixture.commitFile(
      "side.txt", content: "side\n", message: "side", in: source, runner: runner)
    try await LiveRepoFixture.run(["switch", "main"], in: source, runner: runner)

    let options = CloneOptions(depth: 1, singleBranch: true, branch: "main")
    try await SystemGitClient.clone(
      from: source.path,
      to: destination,
      options: options,
      git: LiveRepoFixture.git,
      runner: runner
    ) { _ in }

    let clone = makeClient(destination)
    #expect(try await clone.branches().map(\.name) == ["main"])
    #expect(try await clone.log(LogQuery()).commits.map(\.subject) == ["base"])
  }

  @Test func recursiveCloneChecksOutSubmoduleContent() async throws {
    let git = try LiveRepoFixture.makeFileProtocolGitWrapper()
    let submodule = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "dependency.txt", content: "dependency\n", message: "dependency")],
      runner: runner
    )
    let source = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    let destination = URL.temporaryDirectory
      .appending(path: "spoon-submodule-clone-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: git)
      try? FileManager.default.removeItem(at: submodule)
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: destination)
    }
    try await LiveRepoFixture.run(
      ["-c", "protocol.file.allow=always", "submodule", "add", submodule.path, "Dependency"],
      in: source,
      runner: runner
    )
    try await LiveRepoFixture.run(
      ["commit", "-m", "add submodule"], in: source, runner: runner)

    try await SystemGitClient.clone(
      from: source.path,
      to: destination,
      options: CloneOptions(recurseSubmodules: true),
      git: git,
      runner: runner
    ) { _ in }

    #expect(
      try String(
        contentsOf: destination.appending(path: "Dependency/dependency.txt"),
        encoding: .utf8
      ) == "dependency\n"
    )
  }

  @Test func remotesRoundTripDistinctFetchAndPushURLs() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
    let fetchRemote = try await LiveRepoFixture.makeBareRepo(runner: runner)
    let pushRemote = try await LiveRepoFixture.makeBareRepo(runner: runner)
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: fetchRemote)
      try? FileManager.default.removeItem(at: pushRemote)
    }
    let client = makeClient(root)

    try await client.addRemote(name: "origin", url: fetchRemote.path)
    try await client.setRemoteURL(
      name: "origin",
      fetchURL: fetchRemote.path,
      pushURL: pushRemote.path
    )

    let origin = try #require(try await client.remotes().first)
    #expect(origin.fetchURL == fetchRemote.path)
    #expect(origin.pushURL == pushRemote.path)
  }

  @Test func softAndMixedResetPreserveExpectedState() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "file.txt", content: "one\n", message: "first"),
        .init(file: "file.txt", content: "two\n", message: "second"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    let commits = try await client.log(LogQuery()).commits
    let first = try #require(commits.last)

    try await client.reset(to: first.oid, mode: .soft)
    var status = try await client.status()
    #expect(status.stagedEntries.map(\.path) == ["file.txt"])
    #expect(status.unstagedEntries.isEmpty)
    #expect(try await client.log(LogQuery()).commits.map(\.subject) == ["first"])

    try await LiveRepoFixture.run(["reset", "--hard", "HEAD@{1}"], in: root, runner: runner)
    try await client.reset(to: first.oid, mode: .mixed)
    status = try await client.status()
    #expect(status.stagedEntries.isEmpty)
    #expect(status.unstagedEntries.map(\.path) == ["file.txt"])
    #expect(
      try String(contentsOf: root.appending(path: "file.txt"), encoding: .utf8) == "two\n")
  }
}
