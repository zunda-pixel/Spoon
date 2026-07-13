import Foundation
import Synchronization
import Testing

@testable import SpoonCore

@Suite("SystemGitClient Clone")
struct SystemGitClientCloneTests {
  private let git = URL(filePath: "/usr/bin/git")
  private let baseFlags = ["-c", "color.ui=false", "-c", "core.quotePath=false"]

  @Test func cloneSendsExactArgvAndStreamsProgress() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "clone", "--progress", "https://example.com/repo.git", "/tmp/clone-dest",
      ],
      stderr:
        "Cloning into 'clone-dest'...\nReceiving objects:  50%\rReceiving objects: 100%, done.\n"
    )
    let lines = Mutex<[String]>([])
    try await SystemGitClient.clone(
      from: "https://example.com/repo.git",
      to: URL(filePath: "/tmp/clone-dest"),
      git: git,
      runner: runner
    ) { line in
      lines.withLock { $0.append(line) }
    }
    #expect(runner.invocations.count == 1)
    #expect(lines.withLock { $0.last } == "Receiving objects: 100%, done.")
  }

  @Test func cloneFailureBecomesCommandError() async {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "clone", "--progress", "https://example.com/missing.git", "/tmp/clone-missing",
      ],
      stderr: "fatal: repository not found\n",
      exitCode: 128
    )
    await #expect(throws: CommandError.self) {
      try await SystemGitClient.clone(
        from: "https://example.com/missing.git",
        to: URL(filePath: "/tmp/clone-missing"),
        git: git,
        runner: runner
      ) { _ in }
    }
  }

  @Test func cloneWithOptionsSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: baseFlags + [
        "clone", "--progress",
        "--filter=blob:none",
        "--depth=10",
        "--single-branch",
        "--branch", "main",
        "--recurse-submodules",
        "https://example.com/repo.git", "/tmp/clone-dest",
      ]
    )
    let options = CloneOptions(
      filterBlobNone: true,
      depth: 10,
      singleBranch: true,
      branch: "main",
      recurseSubmodules: true
    )
    try await SystemGitClient.clone(
      from: "https://example.com/repo.git",
      to: URL(filePath: "/tmp/clone-dest"),
      options: options,
      git: git,
      runner: runner
    ) { _ in }
    #expect(runner.invocations.count == 1)
  }
}
