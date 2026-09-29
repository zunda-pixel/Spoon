import Foundation

extension SystemGitClient {

  // MARK: - Tags

  public func tags() async throws -> [Tag] {
    let result = try await run([
      "for-each-ref", "refs/tags",
      "--sort=-creatordate",
      "--format=\(GitTagParser.tagFormat)",
    ])
    return try GitTagParser.parse(result.standardOutput)
  }

  public func createTag(
    name: String, at target: ObjectID?, message: String?, signing: TagSigning
  ) async throws {
    var arguments = ["tag"]
    let message = message.flatMap { $0.isEmpty ? nil : $0 }
    switch (signing, message) {
    case (.sign, _):
      arguments.append(contentsOf: ["--sign", "-m", message ?? name])
    case (.doNotSign, let message?):
      arguments.append(contentsOf: ["--no-sign", "-a", "-m", message])
    case (_, let message?):
      arguments.append(contentsOf: ["-a", "-m", message])
    case (_, nil):
      break
    }
    arguments.append(name)
    if let target {
      arguments.append(target.rawValue)
    }
    try await runVoid(arguments)
  }

  public func verifyTag(name: String) async throws -> CommitSignature? {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["verify-tag", "--raw", "refs/tags/\(name)"],
      timeout: .seconds(30)
    )
    // Failing verification exits non-zero; the output still says why.
    let result = try await runner.run(command)
    let output = result.standardOutputText + "\n" + result.standardErrorText
    return TagVerificationParser.parse(output, exitCode: result.exitCode)
  }

  public func deleteTag(name: String) async throws {
    try await runVoid(["tag", "-d", name])
  }

  public func pushTag(name: String, to remoteName: String) async throws {
    try await runVoid(
      ["push", remoteName, "refs/tags/\(name)"],
      timeout: .seconds(300)
    )
  }

  public func pushAllTags(to remoteName: String) async throws {
    try await runVoid(["push", remoteName, "--tags"], timeout: .seconds(300))
  }

  public func deleteRemoteTag(name: String, from remoteName: String) async throws {
    try await runVoid(
      ["push", remoteName, "--delete", "refs/tags/\(name)"],
      timeout: .seconds(300)
    )
  }
}
