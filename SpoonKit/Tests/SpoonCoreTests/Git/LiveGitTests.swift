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

  @Test func statusAndBranchesOnRealRepo() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    try Data("hello\n".utf8).write(to: root.appending(path: "committed.txt"))
    try await runGit(["add", "."], in: root)
    try await runGit(["commit", "-m", "initial commit"], in: root)

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
    try Data((numbers.joined(separator: "\n") + "\n").utf8)
      .write(to: root.appending(path: "file.txt"))
    try await runGit(["add", "."], in: root)
    try await runGit(["commit", "-m", "base"], in: root)

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

    let staged = try #require(try await client.diffWorkingTree(path: "file.txt", staged: true).first)
    #expect(staged.hunks.count == 1)
    #expect(staged.hunks[0].lines.contains { $0.text == "THIRTY-SIX" })
    #expect(!staged.hunks[0].lines.contains { $0.text == "THREE" })

    let unstaged = try #require(try await client.diffWorkingTree(path: "file.txt", staged: false).first)
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

  @Test func lineDiscardRevertsOnlySelectedLines() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appending(path: "file.txt")
    let numbers = (1...9).map(String.init)
    try Data((numbers.joined(separator: "\n") + "\n").utf8).write(to: file)
    try await runGit(["add", "."], in: root)
    try await runGit(["commit", "-m", "base"], in: root)

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
    let after = try #require(try await client.diffWorkingTree(path: "file.txt", staged: false).first)
    let changed = after.hunks.flatMap(\.lines).filter { $0.kind != .context }.map(\.text)
    #expect(changed.sorted() == ["6", "SIX"])
  }

  @Test func renameDetectionRoundTrip() async throws {
    let root = try await makeTemporaryRepo()
    defer { try? FileManager.default.removeItem(at: root) }

    try Data(String(repeating: "line\n", count: 50).utf8)
      .write(to: root.appending(path: "original.txt"))
    try await runGit(["add", "."], in: root)
    try await runGit(["commit", "-m", "add original"], in: root)
    try await runGit(["mv", "original.txt", "renamed with space.txt"], in: root)

    let client = SystemGitClient(repositoryRoot: root, git: git, runner: runner)
    let status = try await client.status()
    let entry = try #require(status.entries.first)
    #expect(entry.staged == .renamed)
    #expect(entry.path == "renamed with space.txt")
    #expect(entry.originalPath == "original.txt")
  }
}
