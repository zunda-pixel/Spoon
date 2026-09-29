import Foundation

extension SystemGitClient {

  public func branches() async throws -> [Branch] {
    let result = try await run([
      "for-each-ref", "refs/heads",
      "--sort=-committerdate",
      "--format=\(GitRefParser.branchFormat)",
    ])
    return try GitRefParser.parseBranches(result.standardOutput)
  }

  public func switchBranch(_ branch: String) async throws {
    try await runVoid(["switch", branch])
  }

  public func switchToRevision(_ oid: ObjectID) async throws {
    try await runVoid(["switch", "--detach", oid.rawValue])
  }

  public func merge(branch: String, options: MergeOptions) async throws {
    try await runVoid(options.arguments(branch: branch), timeout: .seconds(120))
  }

  public func createBranch(
    name: String,
    from startPoint: String?,
    switchToBranch: Bool
  ) async throws {
    var arguments = switchToBranch ? ["switch", "-c", name] : ["branch", name]
    if let startPoint {
      arguments.append(startPoint)
    }
    try await runVoid(arguments)
  }

  public func switchToRemoteBranch(_ remoteBranch: String) async throws {
    try await runVoid(["switch", "--track", remoteBranch])
  }

  public func deleteBranch(name: String, force: Bool) async throws {
    try await runVoid(["branch", force ? "-D" : "-d", name])
  }

  @discardableResult
  public func deleteMergedBranches(branches: [String], dryRun: Bool) async throws -> [String] {
    // `**` matches every upstream, including names with slashes.
    var arguments = ["branch", "--delete-merged", "**"]
    if dryRun {
      arguments.append("--dry-run")
    }
    arguments.append(contentsOf: branches)
    let result = try await run(arguments)
    return GitRefParser.parseDeletedBranchNames(result.standardOutputText)
  }

  public func renameBranch(from oldName: String, to newName: String) async throws {
    try await runVoid(["branch", "-m", oldName, newName])
  }

  public func moveBranch(name: String, to target: ObjectID, expectedTip: ObjectID) async throws {
    let message = "spoon: move \(name) to \(target.shortened)"
    let reference = "refs/heads/\(name)"
    let command =
      if await capabilities().supportsRefsWriteCommands {
        ["refs", "update", "--message=\(message)"]
      } else {
        ["update-ref", "-m", message]
      }
    try await runVoid(command + [reference, target.rawValue, expectedTip.rawValue])
  }

  public func setUpstream(of branch: String, to upstream: String) async throws {
    try await runVoid(["branch", "--set-upstream-to", upstream, branch])
  }

  public func branchNames(forkedFrom upstream: String) async throws -> [String] {
    if await capabilities().supportsForkedBranchFilter {
      let result = try await run(
        ["branch", "--format=%(refname:short)", "--forked", upstream]
      )
      return result.standardOutputText.split(whereSeparator: \.isNewline).map(String.init)
    }
    // Ref names cannot contain control characters, so a tab separates safely.
    let result = try await run(
      ["for-each-ref", "refs/heads", "--format=%(refname:short)%09%(upstream)"]
    )
    return result.standardOutputText.split(whereSeparator: \.isNewline).compactMap { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 2, fields[1] == upstream else { return nil }
      return String(fields[0])
    }
  }

  public func defaultBranch() async throws -> String {
    if let result = try? await run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) {
      let name = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
      if let slash = name.firstIndex(of: "/") {
        return String(name[name.index(after: slash)...])
      }
    }
    let branches = try await branches()
    if branches.contains(where: { $0.name == "main" }) { return "main" }
    if branches.contains(where: { $0.name == "master" }) { return "master" }
    return branches.first(where: \.isCurrent)?.name ?? "HEAD"
  }
}
