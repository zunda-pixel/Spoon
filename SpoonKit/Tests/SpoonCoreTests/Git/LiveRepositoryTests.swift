import Foundation
import Testing

@testable import SpoonCore

@Suite("Live Repository Operations", .serialized)
struct LiveRepositoryTests {
  private let runner = SubprocessCommandRunner()

  private func makeClient(_ root: URL) -> SystemGitClient {
    LiveRepoFixture.makeClient(for: root, runner: runner)
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
