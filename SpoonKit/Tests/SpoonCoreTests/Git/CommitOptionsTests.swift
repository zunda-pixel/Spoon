import Foundation
import Testing

@testable import SpoonCore

@Suite("Commit options")
struct CommitOptionsTests {
  private let prefix = ["-c", "color.ui=false", "-c", "core.quotePath=false"]

  @Test func optionsBecomeCommitFlags() async throws {
    let runner = FakeCommandRunner()
    let client = SystemGitClient(
      repositoryRoot: URL(filePath: "/tmp/fake-repo"), git: URL(filePath: "/usr/bin/git"),
      runner: runner)
    let expected = [
      ["commit", "-F", "-"],
      ["commit", "-F", "-", "--amend", "--signoff", "--gpg-sign"],
      ["commit", "-F", "-", "--no-gpg-sign"],
    ]
    for arguments in expected {
      runner.stub(arguments: prefix + arguments)
    }

    try await client.commit(message: "plain", amend: false)
    try await client.commit(
      message: "all", options: CommitOptions(amend: true, signOff: true, signing: .sign))
    try await client.commit(message: "unsigned", options: CommitOptions(signing: .doNotSign))

    #expect(runner.invocations.map { Array($0.arguments.dropFirst(prefix.count)) } == expected)
    #expect(runner.invocations[1].standardInput == Data("all".utf8))
  }

  @Test func signingConfigurationReadsGitConfig() async throws {
    let runner = FakeCommandRunner()
    let client = SystemGitClient(
      repositoryRoot: URL(filePath: "/tmp/fake-repo"), git: URL(filePath: "/usr/bin/git"),
      runner: runner)
    runner.stub(
      arguments: prefix + [
        "config", "--get-regexp", #"^(commit\.gpgsign|tag\.gpgsign|gpg\.format|user\.signingkey)$"#,
      ],
      stdout: "user.signingkey ~/.ssh/id_ed25519.pub\ngpg.format ssh\ncommit.gpgsign true\n"
    )

    let configuration = try await client.commitSigningConfiguration()

    #expect(
      configuration
        == CommitSigningConfiguration(
          signsByDefault: true, format: .ssh, key: "~/.ssh/id_ed25519.pub"))
  }

  @Test func signingConfigurationDefaultsAndBooleans() {
    #expect(CommitSigningConfiguration.parse("") == CommitSigningConfiguration())
    #expect(CommitSigningConfiguration.parse("commit.gpgsign\n").signsByDefault)
    #expect(!CommitSigningConfiguration.parse("commit.gpgsign true\ncommit.gpgsign off").signsByDefault)
    #expect(CommitSigningConfiguration.parse("gpg.format X509").format == .x509)
    #expect(CommitSigningConfiguration.parse("tag.gpgsign yes").signsTagsByDefault)
    #expect(!CommitSigningConfiguration.parse("tag.gpgsign yes").signsByDefault)
    #expect(CommitSigningConfiguration().canSign)
    #expect(!CommitSigningConfiguration(format: .ssh).canSign)
  }
}
