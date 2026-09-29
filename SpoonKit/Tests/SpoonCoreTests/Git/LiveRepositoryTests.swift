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

  @MainActor
  @Test func conflictBlocksResolveOneAtATimeAndMarkersCanBeRestored() async throws {
    // Far enough apart that git reports two conflicts, not one.
    let keep = (1...8).map { "keep \($0)\n" }.joined()
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "file.txt", content: "a\n\(keep)b\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.run(["switch", "-c", "topic"], in: root, runner: runner)
    try await LiveRepoFixture.commitFile(
      "file.txt", content: "a topic\n\(keep)b topic\n", message: "topic", in: root,
      runner: runner)
    try await LiveRepoFixture.run(["switch", "main"], in: root, runner: runner)
    try await LiveRepoFixture.commitFile(
      "file.txt", content: "a main\n\(keep)b main\n", message: "main", in: root,
      runner: runner)
    let client = makeClient(root)
    await #expect(throws: CommandError.self) {
      try await client.merge(branch: "topic", options: .standard)
    }
    let model = RepositoryModel(repository: Repository(rootURL: root), gitClient: client)
    let fileURL = root.appending(path: "file.txt")

    let document = try #require(try await model.conflictDocument(path: "file.txt"))
    #expect(document.blocks.count == 2)
    #expect(await model.resolveConflictBlock(document.blocks[0], in: "file.txt", using: .theirs))

    let remaining = try #require(try await model.conflictDocument(path: "file.txt"))
    #expect(remaining.blocks.map(\.ours) == [["b main\n"]])
    #expect(try String(contentsOf: fileURL, encoding: .utf8).hasPrefix("a topic\n\(keep)<<<<<<<"))
    // A block from the old document no longer matches the file.
    #expect(!(await model.resolveConflictBlock(document.blocks[1], in: "file.txt", using: .ours)))

    await model.restoreConflictMarkers(path: "file.txt")
    #expect(try await model.conflictDocument(path: "file.txt")?.blocks.count == 2)
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

  @Test func blameAttributesCommittedAndUncommittedLines() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "f.txt", content: "one\n", message: "first")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.commitFile(
      "f.txt", content: "one\ntwo\n", message: "second", in: root, runner: runner
    )
    try Data("one\ntwo\nthree\n".utf8).write(to: root.appending(path: "f.txt"))

    let lines = try await makeClient(root).blame(path: "f.txt", at: nil)

    #expect(lines.map(\.text) == ["one", "two", "three"])
    #expect(lines.map(\.commit.summary).prefix(2) == ["first", "second"])
    #expect(lines.map(\.commit.isUncommitted) == [false, false, true])
    #expect(lines[0].commit.authorName == "Spoon Tests")
  }

  @Test func bisectFindsTheFirstBadCommit() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: (1...6).map { .init(file: "v.txt", content: "\($0)\n", message: "v\($0)") },
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    // v4 introduces the "bug": any version >= 4 is bad.
    let commits = try await client.log(LogQuery(maxCount: 10)).commits
    let bySubject = Dictionary(uniqueKeysWithValues: commits.map { ($0.subject, $0.oid) })
    func isBad() throws -> Bool {
      let text = try String(contentsOf: root.appending(path: "v.txt"), encoding: .utf8)
      return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))! >= 4
    }

    var progress = try await client.startBisect(bad: bySubject["v6"]!, good: bySubject["v1"]!)
    #expect(try await client.bisectState()?.remainingCount == 4)
    var marks = 0
    while case .testing = progress, marks < 10 {
      progress = try await client.markBisect(try isBad() ? .bad : .good, revision: nil)
      marks += 1
    }

    #expect(progress == .found(bySubject["v4"]!))
    let capabilities = await client.capabilities()
    if !capabilities.supportsBisectResetWhenFound {
      #expect(try await client.bisectState() != nil)
      try await client.resetBisect()
    }
    #expect(try await client.bisectState() == nil)
    #expect(try await client.status().headBranch == "main")
  }

  @Test func historySearchMatchesMessagesAuthorsAndCode() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "a.swift", content: "let answer = 42\n", message: "Add the answer"),
        .init(file: "b.swift", content: "print(1)\n", message: "Fix [crash] on launch"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("print(2)\n".utf8).write(to: root.appending(path: "b.swift"))
    try await LiveRepoFixture.run(["add", "b.swift"], in: root, runner: runner)
    try await LiveRepoFixture.run(
      ["commit", "-m", "Tweak output", "--author", "Other Person <other@example.com>"],
      in: root,
      runner: runner
    )
    let client = makeClient(root)
    func subjects(_ text: String, _ field: HistorySearch.Field) async throws -> [String] {
      let query = LogQuery(allReferences: true, search: HistorySearch(text: text, field: field))
      return try await client.log(query).commits.map(\.subject)
    }

    #expect(try await subjects("[CRASH]", .message) == ["Fix [crash] on launch"])
    #expect(try await subjects("other person", .author) == ["Tweak output"])
    #expect(try await subjects("answer = 42", .code) == ["Add the answer"])
  }

  @Test func pullRebaseReplaysLocalCommitsAndAutostashesChanges() async throws {
    let bare = try await LiveRepoFixture.makeBareRepo(runner: runner)
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    let other = URL.temporaryDirectory.appending(path: "spoon-other-\(UUID().uuidString)")
    defer {
      for url in [bare, root, other] { try? FileManager.default.removeItem(at: url) }
    }
    try await LiveRepoFixture.run(["remote", "add", "origin", bare.path], in: root, runner: runner)
    try await LiveRepoFixture.run(["push", "-u", "origin", "main"], in: root, runner: runner)
    try await LiveRepoFixture.run(
      ["clone", bare.path, other.path], in: URL.temporaryDirectory, runner: runner
    )
    for arguments in [
      ["config", "user.email", "test@example.com"], ["config", "user.name", "Other"],
      ["config", "commit.gpgsign", "false"],
    ] {
      try await LiveRepoFixture.run(arguments, in: other, runner: runner)
    }
    try await LiveRepoFixture.commitFile(
      "remote.txt", content: "r\n", message: "remote change", in: other, runner: runner
    )
    try await LiveRepoFixture.run(["push"], in: other, runner: runner)
    try await LiveRepoFixture.commitFile(
      "local.txt", content: "l\n", message: "local change", in: root, runner: runner
    )
    try Data("edited\n".utf8).write(to: root.appending(path: "base.txt"))
    let client = makeClient(root)

    try await client.pull(PullOptions(strategy: .rebase, autostash: true))

    let commits = try await client.log(LogQuery(maxCount: 5)).commits
    #expect(commits.map(\.subject) == ["local change", "remote change", "base"])
    #expect(commits.allSatisfy { !$0.isMerge })
    #expect(try await client.status().unstagedEntries.map(\.path) == ["base.txt"])
  }

  @Test func restoreFileBringsBackAnOlderVersionWithoutStaging() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [
        .init(file: "f.txt", content: "one\n", message: "one"),
        .init(file: "f.txt", content: "two\n", message: "two"),
        .init(file: "g.txt", content: "new\n", message: "add g"),
      ],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let client = makeClient(root)
    let commits = try await client.log(LogQuery(maxCount: 3)).commits
    let (addG, one) = (commits[0], commits[2])

    try await client.restoreFile(path: "f.txt", from: one.oid)
    try await client.restoreFile(path: "g.txt", from: try #require(addG.parents.first))

    let f = try String(contentsOf: root.appending(path: "f.txt"), encoding: .utf8)
    #expect(f == "one\n")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "g.txt").path))
    let status = try await client.status()
    #expect(status.stagedEntries.isEmpty)
    #expect(Set(status.unstagedEntries.map(\.path)) == ["f.txt", "g.txt"])
  }

  @Test func rangeDiffComparesABranchBeforeAndAfterRewriting() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    func git(_ arguments: [String]) async throws {
      try await LiveRepoFixture.run(arguments, in: root, runner: runner)
    }
    let lines = (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n"
    try await git(["switch", "-c", "topic"])
    try await LiveRepoFixture.commitFile(
      "one.txt", content: lines, message: "add one", in: root, runner: runner
    )
    try await LiveRepoFixture.commitFile(
      "two.txt", content: lines, message: "add two", in: root, runner: runner
    )
    let client = makeClient(root)
    let oldTip = try #require(try await client.branches().first { $0.name == "topic" }).tip
    try Data(lines.replacingOccurrences(of: "line 20", with: "line twenty").utf8)
      .write(to: root.appending(path: "two.txt"))
    try await git(["commit", "-a", "--amend", "--no-edit"])
    let newTip = try #require(try await client.branches().first { $0.name == "topic" }).tip

    #expect(try await client.previousTip(of: "refs/heads/topic") == oldTip)
    #expect(try await client.previousTip(of: "refs/heads/main") == nil)
    let base = try await client.mergeBase("main", "topic")
    let entries = try await client.rangeDiff(
      oldBase: base, oldTip: oldTip, newBase: base, newTip: newTip
    )

    #expect(entries.map(\.relation) == [.unchanged, .changed])
    #expect(entries[1].patchDiff.contains { $0.contains("+line twenty") })
  }

  @Test func filesInANewFolderAreListedAndDiffedOneByOne() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "README.md", content: "readme\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appending(path: "Sources/Update")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("one\n".utf8).write(to: folder.appending(path: "One.swift"))
    try Data("two\n".utf8).write(to: folder.appending(path: "Two.swift"))
    let nested = root.appending(path: "Vendor/Lib")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try await LiveRepoFixture.run(["init", "-q"], in: nested, runner: runner)
    try Data("lib\n".utf8).write(to: nested.appending(path: "lib.txt"))
    let client = makeClient(root)

    let untracked = try await client.status().untrackedEntries.map(\.path)

    #expect(untracked == ["Sources/Update/One.swift", "Sources/Update/Two.swift", "Vendor/Lib/"])
    let diff = try await client.untrackedFileDiff(path: "Sources/Update/One.swift")
    #expect(diff.additionCount == 1)
    await #expect(throws: UntrackedDiffError.nestedRepository(path: "Vendor/Lib/")) {
      try await client.untrackedFileDiff(path: "Vendor/Lib/")
    }
  }

  @Test func squashAndRebaseMergedBranchesCountAsMerged() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    func git(_ arguments: [String]) async throws {
      try await LiveRepoFixture.run(arguments, in: root, runner: runner)
    }
    func commit(_ file: String, _ message: String) async throws {
      try await LiveRepoFixture.commitFile(
        file, content: "\(message)\n", message: message, in: root, runner: runner)
    }
    let branches = [("squashed", ["s1", "s2"]), ("rebased", ["r1", "r2"]), ("open", ["o1"])]
    for (branch, files) in branches {
      try await git(["switch", "-c", branch, "main"])
      for file in files { try await commit("\(file).txt", "\(branch) \(file)") }
    }
    try await git(["switch", "main"])
    try await commit("main.txt", "main moves on")
    try await git(["merge", "--squash", "squashed"])
    try await git(["commit", "-m", "Squash-merge squashed"])
    try await git(["cherry-pick", "main..rebased"])
    let client = makeClient(root)

    #expect(try await client.isContentMerged(branch: "squashed", into: "main"))
    #expect(try await client.isContentMerged(branch: "rebased", into: "main"))
    #expect(try await client.isContentMerged(branch: "open", into: "main") == false)
    // git itself still calls the merged branches unmerged.
    await #expect(throws: CommandError.self) {
      try await client.deleteBranch(name: "squashed", force: false)
    }
  }

  @Test func ignoringWhitespaceHidesWhitespaceOnlyChanges() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "f.swift", content: "func a() {\n  x()\n}\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("func a() {\n    x()\n}\nlet b = 1\n".utf8).write(to: root.appending(path: "f.swift"))
    let client = makeClient(root)

    let full = try await client.diffWorkingTree(path: "f.swift", staged: false)
    let quiet = try await client.diffWorkingTree(
      path: "f.swift", staged: false, options: DiffOptions(ignoresWhitespace: true))

    #expect(full.first?.additionCount == 2)
    #expect(quiet.first?.additionCount == 1)
    #expect(quiet.first?.deletionCount == 0)
  }

  @Test func fixupCommitsAreFoldedByAutosquash() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.commitFile(
      "a.txt", content: "a\n", message: "Add a", in: root, runner: runner)
    try await LiveRepoFixture.commitFile(
      "b.txt", content: "b\n", message: "Add b", in: root, runner: runner)
    let client = makeClient(root)
    let before = try await client.log(LogQuery(maxCount: 3)).commits
    let (addA, base) = (before[1], before[2])

    try Data("a fixed\n".utf8).write(to: root.appending(path: "a.txt"))
    try await client.stage(paths: ["a.txt"])
    try await client.commitFixup(for: addA.oid)
    #expect(try await client.log(LogQuery(maxCount: 1)).commits.first?.subject == "fixup! Add a")

    try await client.autosquash(onto: base.oid)

    let after = try await client.log(LogQuery(maxCount: 3)).commits
    #expect(after.map(\.subject) == ["Add b", "Add a", "base"])
    let detail = try await client.commitDetail(after[1].oid)
    #expect(detail.diffs.first?.hunks.first?.lines.map(\.text) == ["a fixed"])
    #expect(try await client.sequencerState() == nil)
  }

  @Test func severalCommitsArePickedAndRevertedInOrder() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "log.txt", content: "0\n", message: "base")],
      runner: runner
    )
    defer { try? FileManager.default.removeItem(at: root) }
    func git(_ arguments: [String]) async throws {
      try await LiveRepoFixture.run(arguments, in: root, runner: runner)
    }
    try await git(["switch", "-c", "topic"])
    for step in 1...3 {
      let lines = (0...step).map(String.init).joined(separator: "\n") + "\n"
      try await LiveRepoFixture.commitFile(
        "log.txt", content: lines, message: "step \(step)", in: root, runner: runner)
    }
    try await git(["switch", "main"])
    let client = makeClient(root)
    let topic = try await client.log(LogQuery(reference: "topic", maxCount: 3)).commits

    // Each step builds on the previous one, so only oldest-first applies.
    try await client.cherryPick(topic.reversed().map(\.oid))
    let subjects = try await client.log(LogQuery(maxCount: 4)).commits.map(\.subject)
    #expect(subjects == ["step 3", "step 2", "step 1", "base"])

    let picked = try await client.log(LogQuery(maxCount: 2)).commits
    try await client.revert(picked.map(\.oid))
    let file = try String(contentsOf: root.appending(path: "log.txt"), encoding: .utf8)
    #expect(file == "0\n1\n")
  }

  @Test func worktreesLockMoveAndPrune() async throws {
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "base.txt", content: "base\n", message: "base")],
      runner: runner
    )
    let parent = URL.temporaryDirectory.appending(path: "spoon-wt-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: parent)
    }
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    for branch in ["a", "b"] {
      try await LiveRepoFixture.run(["branch", branch], in: root, runner: runner)
    }
    let client = makeClient(root)
    let first = parent.appending(path: "first")
    let moved = parent.appending(path: "moved")
    let doomed = parent.appending(path: "doomed")
    try await client.addWorktree(path: first, branch: "a")
    try await client.addWorktree(path: doomed, branch: "b")
    func worktree(_ branch: String) async throws -> Worktree? {
      try await client.worktrees().first { $0.branch == branch }
    }

    try await client.lockWorktree(path: first, reason: "on external drive")
    #expect(try await worktree("a")?.lockReason == "on external drive")
    await #expect(throws: CommandError.self) {
      try await client.moveWorktree(path: first, to: moved)
    }
    try await client.unlockWorktree(path: first)
    try await client.moveWorktree(path: first, to: moved)
    let movedPath = try #require(try await worktree("a")).path.resolvingSymlinksInPath().path
    #expect(movedPath == moved.resolvingSymlinksInPath().path)

    try FileManager.default.removeItem(at: doomed)
    #expect(try await worktree("b")?.isPrunable == true)
    try await client.pruneWorktrees()
    #expect(try await worktree("b") == nil)
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

  @Test func submodulesCanBeAddedListedDeinitializedAndUpdated() async throws {
    let git = try LiveRepoFixture.makeFileProtocolGitWrapper()
    let library = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "lib.txt", content: "lib\n", message: "lib")],
      runner: runner
    )
    let root = try await LiveRepoFixture.makeTemporaryRepo(
      commits: [.init(file: "app.txt", content: "app\n", message: "app")],
      runner: runner
    )
    defer {
      for url in [git, library, root] { try? FileManager.default.removeItem(at: url) }
    }
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    #expect(try await client.submodules().isEmpty)

    try await client.addSubmodule(url: library.path, path: "Vendor/Lib")
    let added = try await client.submodules()
    #expect(added.map(\.path) == ["Vendor/Lib"])
    #expect(added.first?.state == .upToDate)
    #expect(added.first?.url == library.path)
    #expect(added.first?.name == "Vendor/Lib")

    try await LiveRepoFixture.run(["commit", "-m", "add lib"], in: root, runner: runner)
    try await LiveRepoFixture.run(
      ["submodule", "deinit", "--force", "--", "Vendor/Lib"], in: root, runner: runner)
    #expect(try await client.submodules().first?.state == .notInitialized)

    try await client.syncSubmodules(paths: [])
    try await client.updateSubmodules(paths: ["Vendor/Lib"])
    #expect(try await client.submodules().first?.state == .upToDate)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "Vendor/Lib/lib.txt").path))

    // A local change blocks deinit and removal until it may be discarded.
    let libFile = root.appending(path: "Vendor/Lib/lib.txt")
    try Data("edited\n".utf8).write(to: libFile)
    await #expect(throws: CommandError.self) {
      try await client.deinitializeSubmodule(path: "Vendor/Lib", force: false)
    }
    try await client.deinitializeSubmodule(path: "Vendor/Lib", force: true)
    #expect(try await client.submodules().first?.state == .notInitialized)
    #expect(!FileManager.default.fileExists(atPath: libFile.path))

    try await client.removeSubmodule(path: "Vendor/Lib", force: false)
    #expect(try await client.submodules().isEmpty)
    let staged = try await client.status().stagedEntries.map(\.path).sorted()
    #expect(staged == [".gitmodules", "Vendor/Lib"])
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
