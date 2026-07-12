import Foundation

@testable import SpoonCore

/// Throwaway real-git repositories shared by the Live* suites.
enum LiveRepoFixture {
  static let git = URL(filePath: "/usr/bin/git")

  static func makeTemporaryRepo(runner: SubprocessCommandRunner) async throws -> URL {
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
    return root
  }

  static func run(
    _ arguments: [String], in root: URL, runner: SubprocessCommandRunner
  ) async throws {
    let command = Command(executable: git, arguments: arguments, workingDirectory: root)
    _ = try await runner.run(command).checkSuccess(of: command)
  }
}
