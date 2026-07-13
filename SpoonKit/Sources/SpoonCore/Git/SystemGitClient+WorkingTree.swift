import Foundation

extension SystemGitClient {

  public func status() async throws -> WorkingTreeStatus {
    let result = try await run(["status", "--porcelain=v2", "--branch", "--show-stash", "-z"])
    return try GitStatusParser.parse(result.standardOutput)
  }

  public func diffWorkingTree(path: String?, staged: Bool) async throws -> [FileDiff] {
    var arguments = ["diff"]
    if staged {
      arguments.append("--cached")
    }
    arguments.append("--patch")
    arguments.append("--find-renames")
    arguments.append("--")
    if let path {
      arguments.append(path)
    }
    let result = try await run(arguments)
    return try GitDiffParser.parse(result.standardOutput)
  }

  public func untrackedFileDiff(path: String) async throws -> FileDiff {
    let url = repositoryRoot.appending(path: path)
    let data = try Data(contentsOf: url)
    return UntrackedDiffBuilder.make(path: path, data: data)
  }

  // MARK: - Mutations

  public func stage(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    try await runVoid(["add", "--"] + paths)
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
