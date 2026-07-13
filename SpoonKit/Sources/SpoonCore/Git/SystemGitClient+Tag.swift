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

  public func createTag(name: String, at target: ObjectID?, message: String?) async throws {
    var arguments = ["tag"]
    if let message, !message.isEmpty {
      arguments.append(contentsOf: ["-a", "-m", message])
    }
    arguments.append(name)
    if let target {
      arguments.append(target.rawValue)
    }
    try await runVoid(arguments)
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
