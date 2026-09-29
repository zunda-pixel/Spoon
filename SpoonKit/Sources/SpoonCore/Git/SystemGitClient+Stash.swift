import Foundation

extension SystemGitClient {

  // MARK: - Stashes

  public func stashes() async throws -> [Stash] {
    let result = try await run([
      "stash", "list", "-z", "--format=%H%x1f%P%x1f%gd%x1f%gs",
    ])
    return GitStashParser.parse(result.standardOutput)
  }

  public func saveStash(_ options: StashSaveOptions) async throws {
    try await runVoid(["stash", "push"] + options.arguments)
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
