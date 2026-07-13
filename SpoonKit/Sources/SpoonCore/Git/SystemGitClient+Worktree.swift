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

  public func removeWorktree(path: URL, force: Bool) async throws {
    var arguments = ["worktree", "remove"]
    if force {
      arguments.append("--force")
    }
    arguments.append(path.path)
    try await runVoid(arguments, timeout: .seconds(120))
  }
}
