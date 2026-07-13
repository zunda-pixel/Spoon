import Foundation

@testable import SpoonCore

/// Throwaway real-git repositories shared by the Live* suites.
enum LiveRepoFixture {
  static let git = URL(filePath: "/usr/bin/git")

  struct CommitSpec: Sendable {
    let file: String
    let content: String
    let message: String
  }

  static func makeTemporaryRepo(
    commits: [CommitSpec] = [],
    runner: SubprocessCommandRunner
  ) async throws -> URL {
    let root = URL.temporaryDirectory
      .appending(path: "spoon-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    for arguments in [
      ["init", "--initial-branch=main"],
      ["config", "user.email", "test@example.com"],
      ["config", "user.name", "Spoon Tests"],
      ["config", "commit.gpgsign", "false"],
    ] {
      try await run(arguments, in: root, runner: runner)
    }
    for commit in commits {
      try await commitFile(
        commit.file,
        content: commit.content,
        message: commit.message,
        in: root,
        runner: runner
      )
    }
    return root
  }

  static func makeClient(
    for root: URL,
    runner: SubprocessCommandRunner
  ) -> SystemGitClient {
    SystemGitClient(repositoryRoot: root, git: git, runner: runner)
  }

  static func commitFile(
    _ file: String,
    content: String,
    message: String,
    in root: URL,
    runner: SubprocessCommandRunner
  ) async throws {
    let destination = root.appending(path: file)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(content.utf8).write(to: destination)
    try await run(["add", "--", file], in: root, runner: runner)
    try await run(["commit", "-m", message], in: root, runner: runner)
  }

  static func makeBareRepo(runner: SubprocessCommandRunner) async throws -> URL {
    let root = URL.temporaryDirectory
      .appending(path: "spoon-bare-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try await run(["init", "--bare"], in: root, runner: runner)
    return root
  }

  static func makeFileProtocolGitWrapper() throws -> URL {
    let wrapper = URL.temporaryDirectory
      .appending(path: "spoon-git-\(UUID().uuidString)")
    try Data(
      """
      #!/bin/sh
      exec /usr/bin/git -c protocol.file.allow=always "$@"

      """.utf8
    ).write(to: wrapper)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: wrapper.path
    )
    return wrapper
  }

  static func run(
    _ arguments: [String], in root: URL, runner: SubprocessCommandRunner
  ) async throws {
    let command = Command(executable: git, arguments: arguments, workingDirectory: root)
    _ = try await runner.run(command).checkSuccess(of: command)
  }
}
