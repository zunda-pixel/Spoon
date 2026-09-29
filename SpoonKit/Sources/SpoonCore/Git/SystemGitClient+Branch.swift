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

  public func mergePreview(branch: String) async throws -> MergePreview {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: [
        "merge-tree", "--write-tree", "--name-only", "--no-messages", "-z", "HEAD", branch,
      ],
      timeout: .seconds(60)
    )
    let result = try await runner.run(command)
    switch result.exitCode {
    case 0:
      return MergePreview(conflictedPaths: [])
    case 1:
      // `<tree>\0<path>\0<path>\0…`: the first record is the result tree.
      let records = result.standardOutput.split(separator: 0).dropFirst()
      return MergePreview(
        conflictedPaths: records.map { String(decoding: $0, as: UTF8.self) }
      )
    default:
      _ = try result.checkSuccess(of: command)
      return MergePreview(conflictedPaths: [])
    }
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

  public func isContentMerged(branch: String, into target: String) async throws -> Bool {
    // Rebase merge: each commit has a patch-identical twin in `target`.
    let perCommit = try await run(["cherry", target, branch], timeout: .seconds(60))
    if Self.allCherryPicked(perCommit.standardOutputText) {
      return true
    }
    // Squash merge: the branch's whole change, as one commit on the merge
    // base, has a patch-identical twin in `target`. `commit-tree` only
    // writes an unreferenced object; no ref or the index changes.
    let base = try await run(["merge-base", target, branch])
      .standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    let tree = try await run(["rev-parse", "\(branch)^{tree}"])
      .standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    let squash = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["commit-tree", tree, "-p", base, "-m", "Spoon squash-merge check"],
      // A fixed identity: the check must work without user.name configured.
      extraEnvironment: [
        "GIT_AUTHOR_NAME": "Spoon", "GIT_AUTHOR_EMAIL": "spoon@localhost",
        "GIT_COMMITTER_NAME": "Spoon", "GIT_COMMITTER_EMAIL": "spoon@localhost",
      ],
      timeout: .seconds(30)
    )
    let squashed = try await runner.run(squash).checkSuccess(of: squash)
      .standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    let squashCherry = try await run(["cherry", target, squashed], timeout: .seconds(60))
    return Self.allCherryPicked(squashCherry.standardOutputText)
  }

  /// `git cherry` prints `- <oid>` for commits already upstream and
  /// `+ <oid>` otherwise; nothing means `branch` is already reachable.
  static func allCherryPicked(_ output: String) -> Bool {
    output.split(whereSeparator: \.isNewline).allSatisfy { $0.hasPrefix("-") }
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
