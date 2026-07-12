import Defaults
import Foundation
import SpoonIntent
import Testing

@testable import SpoonCore

/// Lives in OpenRecentRepositoryIntentTests' serialized suite because both
/// fixtures mutate the process-wide Defaults recents key.
extension OpenRecentRepositoryIntentTests {
  private static let git = URL(filePath: "/usr/bin/git")

  private func runGit(
    _ arguments: [String], in root: URL, runner: SubprocessCommandRunner
  ) async throws {
    let command = Command(executable: Self.git, arguments: arguments, workingDirectory: root)
    _ = try await runner.run(command).checkSuccess(of: command)
  }

  private func makeCommittedRepo(runner: SubprocessCommandRunner) async throws -> URL {
    let root = URL.temporaryDirectory
      .appending(path: "spoon-intent-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for arguments in [
      ["init", "--initial-branch=main"],
      ["config", "user.email", "test@example.com"],
      ["config", "user.name", "Spoon Tests"],
      ["config", "commit.gpgsign", "false"],
    ] {
      try await runGit(arguments, in: root, runner: runner)
    }
    try Data("base\n".utf8).write(to: root.appending(path: "base.txt"))
    try await runGit(["add", "."], in: root, runner: runner)
    try await runGit(["commit", "-m", "base"], in: root, runner: runner)
    return root
  }

  @Test func stashChangesStashesTheDirtyRecentRepository() async throws {
    let runner = SubprocessCommandRunner()
    let root = try await makeCommittedRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    let saved = Defaults[.recentRepositoryPaths]
    defer { Defaults[.recentRepositoryPaths] = saved }
    Defaults[.recentRepositoryPaths] = [root.path]

    try Data("dirty\n".utf8).write(to: root.appending(path: "base.txt"))
    try Data("new\n".utf8).write(to: root.appending(path: "untracked.txt"))
    let intent = StashChangesIntent()
    intent.message = "from intent"
    _ = try await intent.perform()

    let client = SystemGitClient(repositoryRoot: root, git: Self.git, runner: runner)
    let stashes = try await client.stashes()
    #expect(stashes.count == 1)
    #expect(stashes[0].message.contains("from intent"))
    #expect(try await client.status().isClean)
  }

  @Test func stashChangesIsANoOpOnACleanRepository() async throws {
    let runner = SubprocessCommandRunner()
    let root = try await makeCommittedRepo(runner: runner)
    defer { try? FileManager.default.removeItem(at: root) }
    let saved = Defaults[.recentRepositoryPaths]
    defer { Defaults[.recentRepositoryPaths] = saved }
    Defaults[.recentRepositoryPaths] = [root.path]

    _ = try await StashChangesIntent().perform()

    let client = SystemGitClient(repositoryRoot: root, git: Self.git, runner: runner)
    #expect(try await client.stashes().isEmpty)
  }
}
