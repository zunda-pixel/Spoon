import Foundation

extension SystemGitClient {

  // MARK: - Stashes

  public func stashes() async throws -> [Stash] {
    let result = try await run([
      "stash", "list", "-z", "--format=%H%x1f%P%x1f%gd%x1f%gs",
    ])
    return GitStashParser.parse(result.standardOutput)
  }

  public func saveStash(message: String?, includeUntracked: Bool) async throws {
    var arguments = ["stash", "push"]
    if includeUntracked {
      arguments.append("--include-untracked")
    }
    if let message, !message.isEmpty {
      arguments.append(contentsOf: ["-m", message])
    }
    try await runVoid(arguments)
  }

  public func applyStash(_ stash: Stash, pop: Bool) async throws {
    try await runVoid(["stash", pop ? "pop" : "apply", stash.reference])
  }

  public func dropStash(_ stash: Stash) async throws {
    try await runVoid(["stash", "drop", stash.reference])
  }

  public func stashDiffs(_ stash: Stash) async throws -> [FileDiff] {
    // `stash show` emits a regular unified diff; --include-untracked also
    // surfaces the untracked-files commit our saveStash records.
    let result = try await run([
      "stash", "show", "--include-untracked", "--patch", "--find-renames", stash.reference,
    ])
    return try GitDiffParser.parse(result.standardOutput)
  }
}
