import Foundation
import Testing

@testable import SpoonCore

/// End-to-end tests against the real git CLI in throwaway repositories.
/// Fast (~100 ms) and hermetic, so they run by default; they are the tripwire
/// for git output-format drift that fixture tests can't catch.
@Suite("LiveGit", .serialized)
struct LiveGitTests {
  private let git = LiveRepoFixture.git
  private let runner = SubprocessCommandRunner()

  private func makeTemporaryRepo() async throws -> URL {
    try await LiveRepoFixture.makeTemporaryRepo(runner: runner)
  }

  private func runGit(_ arguments: [String], in root: URL) async throws {
    try await LiveRepoFixture.run(arguments, in: root, runner: runner)
  }

  @Test func commitsCanBeSignedWithAnSSHKeyAndSignedOff() async throws {
    let root = try await makeTemporaryRepo()
    let keyDirectory = URL.temporaryDirectory.appending(path: "spoon-key-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: keyDirectory)
    }
    try FileManager.default.createDirectory(at: keyDirectory, withIntermediateDirectories: true)
    let key = keyDirectory.appending(path: "id_ed25519")
    let keygen = Command(
      executable: URL(filePath: "/usr/bin/ssh-keygen"),
      arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "spoon-tests", "-f", key.path],
      workingDirectory: keyDirectory
    )
    _ = try await runner.run(keygen).checkSuccess(of: keygen)
    try await runGit(["config", "gpg.format", "ssh"], in: root)
    try await runGit(["config", "user.signingkey", key.path + ".pub"], in: root)
    try Data("signed\n".utf8).write(to: root.appending(path: "signed.txt"))
    try await runGit(["add", "signed.txt"], in: root)
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    let configuration = try await client.commitSigningConfiguration()
    #expect(configuration.format == .ssh)
    #expect(!configuration.signsByDefault)
    try await client.commit(
      message: "signed", options: CommitOptions(signOff: true, signing: .sign))

    let raw = try await client.run(["cat-file", "commit", "HEAD"]).standardOutputText
    #expect(raw.contains("gpgsig -----BEGIN SSH SIGNATURE-----"))
    #expect(raw.contains("Signed-off-by: Spoon Tests <test@example.com>"))

    // Tags: signed on request, and left unsigned despite tag.gpgSign.
    try await runGit(["config", "tag.gpgsign", "true"], in: root)
    #expect(try await client.commitSigningConfiguration().signsTagsByDefault)
    try await client.createTag(name: "v1", at: nil, message: "release", signing: .sign)
    try await client.createTag(name: "v2", at: nil, message: "plain", signing: .doNotSign)
    try await client.createTag(name: "v3", at: nil, message: "configured", signing: .configured)
    let tags = Dictionary(uniqueKeysWithValues: try await client.tags().map { ($0.name, $0) })
    #expect(tags["v1"]?.isSigned == true)
    #expect(tags["v2"]?.isSigned == false)
    #expect(tags["v2"]?.isAnnotated == true)
    #expect(tags["v3"]?.isSigned == true)

    // Verification: SSH needs gpg.ssh.allowedSignersFile to check at all.
    #expect(try await client.verifyTag(name: "v2") == nil)
    let unconfigured = try await client.verifyTag(name: "v1")
    #expect(unconfigured?.status == .unverifiable)
    let publicKey = try String(contentsOf: URL(filePath: key.path + ".pub"), encoding: .utf8)
    let allowed = keyDirectory.appending(path: "allowed_signers")
    try Data("test@example.com \(publicKey)".utf8).write(to: allowed)
    try await runGit(["config", "gpg.ssh.allowedSignersFile", allowed.path], in: root)
    let verified = try await client.verifyTag(name: "v1")
    #expect(verified?.status == .good)
    #expect(verified?.signer == "test@example.com")
  }

  @Test func codeSearchFindsLinesInTheWorkingTreeAndAtARevision() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    try await LiveRepoFixture.commitFile(
      "Sources/Greeting.swift", content: "func greet() {}\nlet name = \"a\"\n",
      message: "greet", in: root, runner: runner)
    try await runGit(["tag", "v1"], in: root)
    try Data("func greet() {}\n// greet again\n".utf8).write(
      to: root.appending(path: "Sources/Greeting.swift"))
    try Data("greet untracked\n".utf8).write(to: root.appending(path: "notes.txt"))
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    let working = try await client.searchCode(CodeSearchQuery(pattern: "GREET"), limit: 100)
    #expect(working.matches.map(\.lineNumber) == [1, 2])
    #expect(working.matches.first?.path == "Sources/Greeting.swift")
    #expect(working.matches.first?.column == 6)

    let untracked = try await client.searchCode(
      CodeSearchQuery(pattern: "greet", includesUntracked: true, paths: ["*.txt"]), limit: 100)
    #expect(untracked.matches.map(\.path) == ["notes.txt"])

    let tagged = try await client.searchCode(
      CodeSearchQuery(pattern: "name", revision: "v1"), limit: 100)
    #expect(tagged.matches.map(\.path) == ["Sources/Greeting.swift"])
    #expect(tagged.matches.map(\.text) == ["let name = \"a\""])

    let none = try await client.searchCode(CodeSearchQuery(pattern: "absent"), limit: 100)
    #expect(none.matches.isEmpty)
    await #expect(throws: CommandError.self) {
      try await client.searchCode(
        CodeSearchQuery(pattern: "(", syntax: .regularExpression), limit: 100)
    }
  }

  @Test func lineHistoryFollowsARangeThroughTheCommitsThatChangedIt() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    func commit(_ content: String, _ message: String) async throws {
      try await LiveRepoFixture.commitFile(
        "notes.txt", content: content, message: message, in: root, runner: runner)
    }
    try await commit("one\ntwo\nthree\n", "add notes")
    try await commit("one\nTWO\nthree\n", "shout two")
    try await commit("zero\none\nTWO\nthree\n", "prepend zero")
    try await commit("zero\none\nTWO\nthree\nfour\n", "append four")
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    // Line 3 is "TWO" now; it was line 2 before "prepend zero" moved it.
    let history = try await client.lineHistory(path: "notes.txt", lines: 3...3, limit: 50)

    #expect(history.map(\.commit.subject) == ["shout two", "add notes"])
    let added = history[0].diffs.first?.hunks.first?.lines.filter { $0.kind == .addition }
    #expect(added?.map(\.text) == ["TWO"])
    #expect(try await client.lineHistory(path: "notes.txt", lines: 3...3, limit: 1).count == 1)
  }

  @Test func repositoryConfigSetsAndUnsetsLocalValues() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    try await client.setRepositoryConfig(.pullRebase, to: "true")
    try await client.setRepositoryConfig(.blameIgnoreRevsFile, to: ".git-blame-ignore-revs")
    var config = try await client.repositoryConfig()
    #expect(config.localValue(.pullRebase) == "true")
    #expect(config.localValue(.blameIgnoreRevsFile) == ".git-blame-ignore-revs")
    // The fixture sets user.name locally.
    #expect(config.localValue(.userName) == "Spoon Tests")

    try await client.setRepositoryConfig(.pullRebase, to: nil)
    // Removing a value that isn't set is not an error.
    try await client.setRepositoryConfig(.fetchPrune, to: nil)
    config = try await client.repositoryConfig()
    #expect(config.localValue(.pullRebase) == nil)
  }

  @Test func changedLinesSearchMatchesARegexWherePickaxeDoesNot() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    func commit(_ content: String, _ message: String) async throws {
      try await LiveRepoFixture.commitFile(
        "f.swift", content: content, message: message, in: root, runner: runner)
    }
    try await commit("let count = 1\n", "add count")
    try await commit("let count = 1\nfunc runSearch() {}\n", "add search")
    // Changes the line around the match without changing how often it occurs.
    try await commit("let count = 2\nfunc runSearch() {}\n", "bump count")
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    func subjects(_ search: HistorySearch) async throws -> [String] {
      try await client.log(LogQuery(allReferences: true, search: search)).commits.map(\.subject)
    }

    #expect(
      try await subjects(HistorySearch(text: "FUNC [a-z]+search", field: .changedLines))
        == ["add search"])
    #expect(
      try await subjects(HistorySearch(text: "count = [0-9]+", field: .changedLines))
        == ["bump count", "add count"])
    // The pickaxe only sees commits that change how often the text occurs.
    #expect(try await subjects(HistorySearch(text: "count", field: .code)) == ["add count"])
  }

  @Test func describePlacesACommitBetweenTags() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    func commit(_ message: String) async throws {
      try await LiveRepoFixture.commitFile(
        "f.txt", content: message, message: message, in: root, runner: runner)
    }
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    func oid(_ revision: String) async throws -> ObjectID {
      let text = try await client.run(["rev-parse", revision]).standardOutputText
      return try #require(ObjectID(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    try await commit("one")
    #expect(try await client.describe(try await oid("HEAD")).isEmpty)
    try await runGit(["tag", "release-1"], in: root)
    try await commit("two")
    try await commit("three")
    try await runGit(["tag", "-a", "-m", "second", "release-2"], in: root)
    try await commit("four")

    let two = try await client.describe(try await oid("HEAD~2"))
    #expect(two == CommitDescription(nearestTag: "release-1", commitsSinceTag: 1, firstContainingTag: "release-2"))
    let tagged = try await client.describe(try await oid("release-2"))
    #expect(tagged.nearestTag == "release-2")
    #expect(tagged.commitsSinceTag == 0)
    #expect(tagged.firstContainingTag == "release-2")
    let unreleased = try await client.describe(try await oid("HEAD"))
    #expect(unreleased.nearestTag == "release-2")
    #expect(unreleased.commitsSinceTag == 1)
    #expect(unreleased.firstContainingTag == nil)
  }

  @Test func statusAndBranchesOnRealRepo() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    try await LiveRepoFixture.commitFile(
      "committed.txt",
      content: "hello\n",
      message: "initial commit",
      in: root,
      runner: runner
    )

    try Data("dirty\n".utf8).write(to: root.appending(path: "committed.txt"))
    try Data("new\n".utf8).write(to: root.appending(path: "untracked file.txt"))
    try Data("staged\n".utf8).write(to: root.appending(path: "staged.txt"))
    try await runGit(["add", "staged.txt"], in: root)

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    let status = try await client.status()
    #expect(status.headBranch == "main")
    #expect(status.headOID != nil)
    #expect(status.stagedEntries.map(\.path) == ["staged.txt"])
    #expect(status.unstagedEntries.map(\.path) == ["committed.txt"])
    #expect(status.untrackedEntries.map(\.path) == ["untracked file.txt"])

    let branches = try await client.branches()
    #expect(branches.count == 1)
    #expect(branches[0].name == "main")
    #expect(branches[0].isCurrent)
    #expect(branches[0].subject == "initial commit")
  }

  @Test func initializeCreatesRepositoryWithRequestedBranch() async throws {
    let root = URL.temporaryDirectory.appending(path: "spoon-init-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    try await SystemGitClient.initialize(
      at: root,
      initialBranch: "develop",
      git: git,
      runner: runner
    )

    #expect(FileManager.default.fileExists(atPath: root.appending(path: ".git").path))
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let status = try await client.status()
    #expect(status.headBranch == "develop")
    #expect(status.headOID == nil)
  }

  @Test func unbornRepoHasNoHeadOID() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let status = try await client.status()
    #expect(status.headOID == nil)
    #expect(status.headBranch == "main")
  }

  @Test func discoversRepositoryRootFromSubdirectory() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    let nested = root.appending(path: "deep/nested/dir")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    let found = await SystemGitClient.repositoryRoot(containing: nested, git: git, runner: runner)
    // Temp dirs sit behind symlinks and directory URLs render a trailing
    // slash; compare fully resolved Repository identities instead.
    #expect(
      found.map { Repository(rootURL: $0.resolvingSymlinksInPath()) }
        == Repository(rootURL: root.resolvingSymlinksInPath())
    )

    let notARepo = await SystemGitClient.repositoryRoot(
      containing: URL(filePath: "/System/Library"),
      git: git,
      runner: runner
    )
    #expect(notARepo == nil)
  }

  @Test func hunkStagingRoundTrip() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    // Commit a file long enough to yield two separate hunks.
    let numbers = (1...40).map(String.init)
    try await LiveRepoFixture.commitFile(
      "file.txt",
      content: numbers.joined(separator: "\n") + "\n",
      message: "base",
      in: root,
      runner: runner
    )

    // Edit near the top and near the bottom.
    var edited = numbers
    edited[2] = "THREE"
    edited[35] = "THIRTY-SIX"
    try Data((edited.joined(separator: "\n") + "\n").utf8)
      .write(to: root.appending(path: "file.txt"))

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let diff = try #require(try await client.diffWorkingTree(path: "file.txt", staged: false).first)
    #expect(diff.hunks.count == 2)

    // Stage ONLY the second hunk.
    let patch = try #require(DiffPatchBuilder.patch(for: diff, including: [diff.hunks[1].id]))
    try await client.applyPatch(patch, reverse: false, toIndex: true)

    let staged = try #require(
      try await client.diffWorkingTree(path: "file.txt", staged: true).first)
    #expect(staged.hunks.count == 1)
    #expect(staged.hunks[0].lines.contains { $0.text == "THIRTY-SIX" })
    #expect(!staged.hunks[0].lines.contains { $0.text == "THREE" })

    let unstaged = try #require(
      try await client.diffWorkingTree(path: "file.txt", staged: false).first)
    #expect(unstaged.hunks.count == 1)
    #expect(unstaged.hunks[0].lines.contains { $0.text == "THREE" })

    // Unstage it again — the index returns to HEAD.
    try await client.applyPatch(patch, reverse: true, toIndex: true)
    let afterUnstage = try await client.diffWorkingTree(path: "file.txt", staged: true)
    #expect(afterUnstage.isEmpty)
  }

  @Test func stageCommitAndHistoryRoundTrip() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    try Data("v1\n".utf8).write(to: root.appending(path: "file.txt"))
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    try await client.stage(paths: ["file.txt"])
    try await client.commit(message: "feat: first\n\nBody line.", amend: false)

    try Data("v2\n".utf8).write(to: root.appending(path: "file.txt"))
    try await client.stage(paths: ["file.txt"])
    try await client.commit(message: "feat: second", amend: false)

    let page = try await client.log(LogQuery())
    #expect(page.commits.map(\.subject) == ["feat: second", "feat: first"])
    #expect(!page.hasMore)

    let detail = try await client.commitDetail(page.commits[0].oid)
    #expect(detail.fullMessage == "feat: second")
    #expect(detail.diffs.count == 1)
    #expect(detail.diffs[0].hunks[0].lines.map(\.text) == ["v1", "v2"])

    let first = try await client.commitDetail(page.commits[1].oid)
    #expect(first.fullMessage.contains("Body line."))
    #expect(first.diffs[0].kind == .added)
  }

  @Test func fileHistoryResetAndReflogRoundTrip() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)

    try await LiveRepoFixture.commitFile(
      "tracked.txt", content: "base\n", message: "base", in: root, runner: runner)
    let base = try #require(try await client.log(LogQuery()).commits.first)

    try await LiveRepoFixture.commitFile(
      "other.txt", content: "other\n", message: "other", in: root, runner: runner)

    let filePage = try await client.log(LogQuery(path: "tracked.txt"))
    #expect(filePage.commits.map(\.subject) == ["base"])

    try await client.reset(to: base.oid, mode: .hard)
    #expect(try await client.log(LogQuery()).commits.map(\.subject) == ["base"])
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "other.txt").path))

    let reflog = try await client.reflog(maxCount: 20, skip: 0)
    #expect(reflog.contains { $0.subject.contains("reset: moving to") })
  }

  @Test func lineDiscardRevertsOnlySelectedLines() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appending(path: "file.txt")
    let numbers = (1...9).map(String.init)
    try await LiveRepoFixture.commitFile(
      "file.txt",
      content: numbers.joined(separator: "\n") + "\n",
      message: "base",
      in: root,
      runner: runner
    )

    // Two edits inside one hunk: line 4 and line 6.
    var edited = numbers
    edited[3] = "FOUR"
    edited[5] = "SIX"
    try Data((edited.joined(separator: "\n") + "\n").utf8).write(to: file)

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let diff = try #require(try await client.diffWorkingTree(path: "file.txt", staged: false).first)
    let hunk = try #require(diff.hunks.first)
    #expect(diff.hunks.count == 1)

    // Select ONLY the -4/+FOUR pair.
    let fourOffsets = Set(
      hunk.lines.indices.filter { hunk.lines[$0].text == "4" || hunk.lines[$0].text == "FOUR" }
    )
    #expect(fourOffsets.count == 2)
    let patch = try #require(
      DiffPatchBuilder.discardPatch(for: diff, hunkID: hunk.id, selectedOffsets: fourOffsets)
    )
    try await client.applyPatch(patch, reverse: true, toIndex: false)

    // Line 4 reverted; line 6 still edited.
    var expected = numbers
    expected[5] = "SIX"
    let contents = try String(contentsOf: file, encoding: .utf8)
    #expect(contents == expected.joined(separator: "\n") + "\n")

    // Remaining diff shows only the SIX edit.
    let after = try #require(
      try await client.diffWorkingTree(path: "file.txt", staged: false).first)
    let changed = after.hunks.flatMap(\.lines).filter { $0.kind != .context }.map(\.text)
    #expect(changed.sorted() == ["6", "SIX"])
  }

  @Test func renameDetectionRoundTrip() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    try await LiveRepoFixture.commitFile(
      "original.txt",
      content: String(repeating: "line\n", count: 50),
      message: "add original",
      in: root,
      runner: runner
    )
    try await runGit(["mv", "original.txt", "renamed with space.txt"], in: root)

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let status = try await client.status()
    let entry = try #require(status.entries.first)
    #expect(entry.staged == .renamed)
    #expect(entry.path == "renamed with space.txt")
    #expect(entry.originalPath == "original.txt")
  }
}
