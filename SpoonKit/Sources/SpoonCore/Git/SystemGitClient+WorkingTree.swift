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

  public func restoreConflictMarkers(path: String) async throws {
    try await runVoid(["checkout", "--merge", "--", path])
  }

  public func rerereRemaining() async throws -> Set<String>? {
    // MERGE_RR records the conflicts rerere is tracking; without it,
    // `rerere remaining` prints nothing and means nothing.
    let paths = try await repositoryPaths()
    let mergeRR = paths.gitDirectory.appending(path: "MERGE_RR")
    guard FileManager.default.fileExists(atPath: mergeRR.path) else { return nil }
    let result = try await run(["rerere", "remaining"])
    return Set(result.standardOutputText.split(whereSeparator: \.isNewline).map(String.init))
  }

  public func forgetRecordedResolution(path: String) async throws {
    try await runVoid(["rerere", "forget", "--", path])
  }

  public func forgetAllRecordedResolutions() async throws {
    let paths = try await repositoryPaths()
    let cache = paths.commonDirectory.appending(path: "rr-cache", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: cache.path) else { return }
    try FileManager.default.removeItem(at: cache)
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

  public func ignoredPaths() async throws -> [String] {
    let result = try await run(
      ["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"],
      timeout: .seconds(60)
    )
    return result.standardOutputText.split(separator: "\0").map(String.init)
  }

  public func ignoreRules(for paths: [String]) async throws -> [String: IgnoreRule?] {
    guard !paths.isEmpty else { return [:] }
    var command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["check-ignore", "--stdin", "-z", "--verbose", "--non-matching"],
      timeout: .seconds(60)
    )
    command.standardInput = Data(paths.map { $0 + "\0" }.joined().utf8)
    let result = try await runner.run(command)
    // Exit 1 means no path matched a pattern; the records still list them.
    if result.exitCode != 1 { _ = try result.checkSuccess(of: command) }
    return IgnoreRule.parse(result.standardOutputText)
  }

  public func deleteIgnored(paths: [String]) async throws {
    // Build folders can be large; give the delete time.
    try await runVoid(["clean", "-f", "-d", "-X", "--"] + paths, timeout: .seconds(300))
  }

  public func skipWorktreePaths() async throws -> [String] {
    let result = try await run(["ls-files", "-v", "-z"], timeout: .seconds(60))
    let root = repositoryRoot
    return result.standardOutputText.split(separator: "\0").compactMap { record in
      // `S <path>`: S marks the skip-worktree bit (lowercase s would be
      // assume-unchanged as well).
      guard record.hasPrefix("S ") || record.hasPrefix("s ") else { return nil }
      let path = String(record.dropFirst(2))
      return FileManager.default.fileExists(atPath: root.appending(path: path).path) ? path : nil
    }.sorted()
  }

  public func setSkipWorktree(paths: [String], skip: Bool) async throws {
    guard !paths.isEmpty else { return }
    try await runVoid(
      ["update-index", skip ? "--skip-worktree" : "--no-skip-worktree", "--"] + paths)
    guard skip else { return }
    // With sparse checkout on, git keeps the bit to its own rules and
    // silently leaves it off; say so rather than appear to have worked.
    let result = try await run(["ls-files", "-v", "-z", "--"] + paths)
    let unset = result.standardOutputText.split(separator: "\0").filter {
      !($0.hasPrefix("S ") || $0.hasPrefix("s "))
    }
    if !unset.isEmpty { throw SkipWorktreeError.managedBySparseCheckout }
  }

  public func isTracked(path: String) async throws -> Bool {
    let result = try await run(["ls-files", "-z", "--", path])
    return !result.standardOutput.isEmpty
  }

  public func commitFixup(for oid: ObjectID) async throws {
    try await runVoid(
      ["commit", "--fixup=\(oid.rawValue)"],
      extraEnvironment: ["GIT_EDITOR": "true"],
      timeout: .seconds(120)
    )
  }

  public func commit(message: String, options: CommitOptions) async throws {
    // Generous timeout: user hooks may run, and a signing agent may ask
    // for a passphrase.
    try await runVoid(
      ["commit", "-F", "-"] + options.arguments,
      standardInput: Data(message.utf8),
      timeout: .seconds(120)
    )
  }

  public func repositoryConfig() async throws -> RepositoryConfig {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["config", "--null", "--show-scope", "--get-regexp", RepositorySetting.pattern],
      timeout: .seconds(10)
    )
    let result = try await runner.run(command)
    // `git config --get-regexp` exits 1 when nothing matches.
    if result.exitCode == 1 { return RepositoryConfig() }
    return RepositoryConfig(
      entries: GitConfigEntry.parse(try result.checkSuccess(of: command).standardOutputText))
  }

  public func setRepositoryConfig(_ setting: RepositorySetting, to value: String?) async throws {
    guard let value else {
      let command = GitCommand.make(
        git: git,
        repository: repositoryRoot,
        arguments: ["config", "--local", "--unset-all", setting.rawValue],
        timeout: .seconds(10)
      )
      let result = try await runner.run(command)
      // Exit 5: nothing to unset, which is the state asked for.
      if result.exitCode != 5 { _ = try result.checkSuccess(of: command) }
      return
    }
    try await runVoid(["config", "--local", "--replace-all", setting.rawValue, value])
  }

  public func commitSigningConfiguration() async throws -> CommitSigningConfiguration {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: [
        "config", "--get-regexp", #"^(commit\.gpgsign|tag\.gpgsign|gpg\.format|user\.signingkey)$"#,
      ],
      timeout: .seconds(10)
    )
    let result = try await runner.run(command)
    // `git config --get-regexp` exits 1 when nothing matches.
    if result.exitCode == 1 { return CommitSigningConfiguration() }
    return CommitSigningConfiguration.parse(
      try result.checkSuccess(of: command).standardOutputText)
  }

  public func reset(to target: ObjectID, mode: ResetMode) async throws {
    try await runVoid(["reset", "--\(mode.rawValue)", target.rawValue])
  }
}
