import Foundation

extension SystemGitClient {

  public func repositoryPaths() async throws -> GitRepositoryPaths {
    let parsed: GitRepositoryPaths?
    if await capabilities().supportsRepoInfoPaths {
      let result = try await run(
        [
          "repo", "info", "-z",
          GitRepositoryPathsParser.gitDirectoryKey,
          GitRepositoryPathsParser.commonDirectoryKey,
        ],
        timeout: .seconds(10)
      )
      parsed = GitRepositoryPathsParser.parseRepoInfo(result.standardOutput)
    } else {
      let result = try await run(
        ["rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir"],
        timeout: .seconds(10)
      )
      parsed = GitRepositoryPathsParser.parseRevParse(result.standardOutputText)
    }
    guard let parsed else { throw GitRepositoryPathsError.unrecognizedOutput }
    return parsed
  }

  public func status() async throws -> WorkingTreeStatus {
    // `all` lists each file of a new folder instead of one `folder/` entry,
    // so every untracked file can be diffed, staged, and discarded on its own.
    let result = try await run([
      "status", "--porcelain=v2", "--branch", "--show-stash", "--untracked-files=all", "-z",
    ])
    return try GitStatusParser.parse(result.standardOutput)
  }

  public func diffWorkingTree(
    path: String?, staged: Bool, options: DiffOptions
  ) async throws -> [FileDiff] {
    var arguments = ["diff"]
    if staged {
      arguments.append("--cached")
    }
    arguments.append("--patch")
    arguments.append("--find-renames")
    arguments.append(contentsOf: options.arguments)
    arguments.append("--")
    if let path {
      arguments.append(path)
    }
    let result = try await run(arguments)
    return try GitDiffParser.parse(result.standardOutput)
  }

  public func untrackedFileDiff(path: String) async throws -> FileDiff {
    let url = repositoryRoot.appending(path: path)
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
      // Even with --untracked-files=all, git reports a nested repository as
      // a single folder entry.
      throw UntrackedDiffError.nestedRepository(path: path)
    }
    let data = try Data(contentsOf: url)
    return UntrackedDiffBuilder.make(path: path, data: data)
  }

  // MARK: - Mutations

  public func stage(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    try await runVoid(["add", "--"] + paths)
  }

  public func markResolved(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    if await capabilities().supportsAddResolved {
      try await runVoid(["add", "--resolved", "--"] + paths)
    } else {
      try await runVoid(["add", "--"] + paths)
    }
  }

  public func resolveConflict(
    path: String,
    using side: FileStatusEntry.ConflictSide,
    sideHasFile: Bool
  ) async throws {
    if sideHasFile {
      try await runVoid(["checkout", "--\(side.rawValue)", "--", path])
      try await runVoid(["add", "--", path])
    } else {
      try await runVoid(["rm", "--quiet", "--", path])
    }
  }

  public func restoreFile(path: String, from revision: ObjectID) async throws {
    try await runVoid(["restore", "--source=\(revision.rawValue)", "--worktree", "--", path])
  }

  public func unstage(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    do {
      try await runVoid(["restore", "--staged", "--"] + paths)
    } catch {
      // `restore --staged` needs HEAD; on an unborn branch drop the
      // paths from the index instead.
      try await runVoid(["rm", "-r", "--cached", "-q", "--"] + paths)
    }
  }

  public func applyPatch(_ patch: String, reverse: Bool, toIndex: Bool) async throws {
    var arguments = ["apply", "--whitespace=nowarn"]
    if toIndex {
      arguments.append("--cached")
    }
    if reverse {
      arguments.append("-R")
    }
    arguments.append("-")
    try await runVoid(arguments, standardInput: Data(patch.utf8))
  }

  public func discardWorkingTree(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    try await runVoid(["restore", "--"] + paths)
  }

  public func deleteUntracked(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    try await runVoid(["clean", "-f", "--"] + paths)
  }

  public func commit(message: String, amend: Bool) async throws {
    var arguments = ["commit", "-F", "-"]
    if amend {
      arguments.append("--amend")
    }
    // Generous timeout: user hooks may run.
    try await runVoid(arguments, standardInput: Data(message.utf8), timeout: .seconds(120))
  }

  public func reset(to target: ObjectID, mode: ResetMode) async throws {
    try await runVoid(["reset", "--\(mode.rawValue)", target.rawValue])
  }
}
