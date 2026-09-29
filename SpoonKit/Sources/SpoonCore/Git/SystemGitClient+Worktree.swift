public import Foundation

extension SystemGitClient {

  // MARK: - Worktrees

  public func worktrees() async throws -> [Worktree] {
    let result = try await run(["worktree", "list", "--porcelain"])
    return WorktreeParser.parse(result.standardOutput)
  }

  public func addWorktree(path: URL, branch: String) async throws {
    try await runVoid(["worktree", "add", path.path, branch], timeout: .seconds(120))
  }

  public func addWorktree(
    path: URL,
    remoteBranch: String,
    localBranch: String
  ) async throws {
    try await runVoid(
      ["worktree", "add", "--track", "-b", localBranch, path.path, remoteBranch],
      timeout: .seconds(120)
    )
  }

  public func removeWorktree(path: URL, force: Bool) async throws {
    var arguments = ["worktree", "remove"]
    if force {
      arguments.append("--force")
    }
    arguments.append(path.path)
    try await runVoid(arguments, timeout: .seconds(120))
  }

  public func pruneWorktrees() async throws {
    try await runVoid(["worktree", "prune"])
  }

  public func lockWorktree(path: URL, reason: String?) async throws {
    var arguments = ["worktree", "lock"]
    if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
      arguments.append(contentsOf: ["--reason", reason])
    }
    arguments.append(path.path)
    try await runVoid(arguments)
  }

  public func unlockWorktree(path: URL) async throws {
    try await runVoid(["worktree", "unlock", path.path])
  }

  public func moveWorktree(path: URL, to destination: URL) async throws {
    try await runVoid(["worktree", "move", path.path, destination.path], timeout: .seconds(120))
  }
}
