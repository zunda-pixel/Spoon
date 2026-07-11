import Foundation
import Testing

@testable import SpoonCore

@Suite("SystemGitClient")
struct SystemGitClientTests {
  private let root = URL(filePath: "/tmp/fake-repo")
  private let git = URL(filePath: "/usr/bin/git")

  private func makeClient(_ runner: FakeCommandRunner) -> SystemGitClient {
    SystemGitClient(repositoryRoot: root, git: git, runner: runner)
  }

  @Test func statusSendsExactArgvAndEnvironment() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "status", "--porcelain=v2", "--branch", "--show-stash", "-z",
      ],
      stdout: "# branch.oid 4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331\u{0}# branch.head main\u{0}"
    )

    let status = try await makeClient(runner).status()
    #expect(status.headBranch == "main")

    let command = try #require(runner.invocations.first)
    #expect(command.executable == git)
    #expect(command.workingDirectory == root)
    #expect(command.environment["GIT_TERMINAL_PROMPT"] == "0")
    #expect(command.environment["GIT_OPTIONAL_LOCKS"] == "0")
    #expect(command.environment["LC_ALL"] == "C")
  }

  @Test func branchesSendsExactArgv() async throws {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "for-each-ref", "refs/heads",
        "--sort=-committerdate",
        "--format=\(GitRefParser.branchFormat)",
      ],
      stdout: "*\u{0}main\u{0}4ae2b1babc8e42f9dc9e34b7de1836a10ed4c331\u{0}subject\u{0}\u{0}\u{0}1720000000\n"
    )

    let branches = try await makeClient(runner).branches()
    #expect(branches.count == 1)
    #expect(branches[0].isCurrent)
  }

  @Test func nonZeroExitBecomesCommandError() async {
    let runner = FakeCommandRunner()
    runner.stub(
      arguments: [
        "-c", "color.ui=false",
        "-c", "core.quotePath=false",
        "status", "--porcelain=v2", "--branch", "--show-stash", "-z",
      ],
      stderr: "fatal: not a git repository\n",
      exitCode: 128
    )

    await #expect(throws: CommandError.self) {
      try await makeClient(runner).status()
    }
  }

  @Test func parsesRemoteListing() {
    let remotes = SystemGitClient.parseRemotes(
      """
      origin\tgit@github.com:owner/repo.git (fetch)
      origin\tgit@github.com:owner/repo.git (push)
      fork\thttps://github.com/me/repo.git (fetch)
      fork\thttps://github.com/me/push-elsewhere.git (push)
      """
    )
    #expect(remotes.count == 2)
    #expect(remotes[0].name == "origin")
    #expect(remotes[0].fetchURL == "git@github.com:owner/repo.git")
    #expect(remotes[0].pushURL == nil)
    #expect(remotes[1].name == "fork")
    #expect(remotes[1].pushURL == "https://github.com/me/push-elsewhere.git")
  }
}
