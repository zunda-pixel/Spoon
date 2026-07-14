import Foundation

extension SystemGitClient {

  public func remotes() async throws -> [Remote] {
    let result = try await run(["remote", "-v"])
    return GitRemoteParser.parse(result.standardOutputText)
  }

  public func remoteBranches(of remoteName: String) async throws -> [Branch] {
    let result = try await run([
      "for-each-ref", "refs/remotes/\(remoteName)",
      "--sort=-committerdate",
      "--format=\(GitRefParser.branchFormat)",
    ])
    // HEAD/upstream fields are empty for remote refs; the parser maps them
    // to isCurrent=false / upstream=nil, which is exactly right here.
    return try GitRefParser.parseBranches(result.standardOutput)
  }

  public func addRemote(name: String, url: String) async throws {
    try await runVoid(["remote", "add", name, url])
  }

  public func setRemoteURL(name: String, fetchURL: String, pushURL: String?) async throws {
    try await runVoid(["remote", "set-url", name, fetchURL])
    try await runVoid(["remote", "set-url", "--push", name, pushURL ?? fetchURL])
  }

  public func removeRemote(name: String) async throws {
    try await runVoid(["remote", "remove", name])
  }

  public func renameRemoteBranch(
    remoteName: String,
    from oldName: String,
    to newName: String
  ) async throws {
    try await runVoid(
      [
        "push",
        remoteName,
        "refs/remotes/\(remoteName)/\(oldName):refs/heads/\(newName)",
      ],
      timeout: .seconds(300)
    )
    try await deleteRemoteBranch(name: oldName, from: remoteName)
  }

  public func deleteRemoteBranch(name: String, from remoteName: String) async throws {
    try await runVoid(
      ["push", remoteName, "--delete", name],
      timeout: .seconds(300)
    )
  }

  public func fetch() async throws {
    try await runVoid(["fetch", "--all", "--prune"], timeout: .seconds(300))
  }

  public func supportsBackfill() async -> Bool {
    guard let result = try? await run(["version"], timeout: .seconds(10)) else { return false }
    return GitVersionParser.supportsBackfill(result.standardOutputText)
  }

  public func backfill() async throws {
    try await runVoid(["backfill"], timeout: .seconds(3600))
  }

  public func pull() async throws {
    try await runVoid(["pull"], timeout: .seconds(300))
  }

  public func push(force: Bool) async throws {
    var arguments = ["push"]
    if force {
      arguments.append("--force-with-lease")
    }
    do {
      try await runVoid(arguments, timeout: .seconds(300))
    } catch let error as CommandError {
      // First push of a new branch: set upstream and retry once.
      if error.standardErrorExcerpt.contains("--set-upstream") {
        var upstreamArguments = ["push"]
        if force {
          upstreamArguments.append("--force-with-lease")
        }
        upstreamArguments.append(contentsOf: ["--set-upstream", "origin", "HEAD"])
        try await runVoid(
          upstreamArguments,
          timeout: .seconds(300)
        )
      } else {
        throw error
      }
    }
  }

  /// `git remote -v` → `name\turl (fetch)` / `name\turl (push)` lines.
  static func parseRemotes(_ text: String) -> [Remote] {
    GitRemoteParser.parse(text)
  }
}
