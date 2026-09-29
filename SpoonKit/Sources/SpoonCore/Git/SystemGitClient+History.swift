import Foundation

extension SystemGitClient {

  public func log(_ query: LogQuery) async throws -> LogPage {
    var arguments = [
      "log", "--topo-order", "-z",
      "--format=\(GitLogParser.logFormat)",
      // One extra row tells us whether another page exists.
      "--max-count=\(query.maxCount + 1)",
    ]
    if query.skip > 0 {
      arguments.append("--skip=\(query.skip)")
    }
    if query.followRenames, query.path != nil {
      arguments.append("--follow")
    }
    if let search = query.search {
      arguments.append(contentsOf: search.arguments)
    }
    if query.allReferences {
      arguments.append("--all")
    }
    if !query.references.isEmpty {
      arguments.append(contentsOf: query.references)
    } else if let reference = query.reference {
      arguments.append(reference)
    } else if !query.allReferences {
      arguments.append("HEAD")
    }
    if !query.excludedReferences.isEmpty {
      arguments.append("--not")
      arguments.append(contentsOf: query.excludedReferences)
    }
    arguments.append(contentsOf: query.additionalRevisions.map(\.rawValue))
    arguments.append("--")
    if let path = query.path {
      arguments.append(path)
    }
    // A code search diffs every commit, so allow it much longer.
    let result = try await run(arguments, timeout: .seconds(query.search == nil ? 30 : 180))
    var commits = try GitLogParser.parse(result.standardOutput)
    let hasMore = commits.count > query.maxCount
    if hasMore {
      commits.removeLast()
    }
    return LogPage(commits: commits, hasMore: hasMore)
  }

  public func reflog(maxCount: Int, skip: Int) async throws -> [ReflogEntry] {
    var arguments = [
      "reflog", "show", "-z",
      "--format=\(GitReflogParser.format)",
      "--max-count=\(maxCount)",
    ]
    if skip > 0 {
      arguments.append("--skip=\(skip)")
    }
    let result = try await run(arguments)
    return try GitReflogParser.parse(result.standardOutput)
  }

  public func blameIgnoreRevsFiles() async throws -> [String] {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["config", "--get-all", "blame.ignoreRevsFile"],
      timeout: .seconds(10)
    )
    let result = try await runner.run(command)
    // `git config --get-all` exits 1 when the key is unset.
    if result.exitCode == 1 { return [] }
    return try result.checkSuccess(of: command).standardOutputText
      .split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
  }

  public func blame(path: String, at revision: ObjectID?, options: BlameOptions) async throws
    -> [BlameLine]
  {
    var arguments = ["blame", "--porcelain"] + options.arguments
    if let revision {
      arguments.append(revision.rawValue)
    }
    arguments.append(contentsOf: ["--", path])
    let result = try await run(arguments, timeout: .seconds(120))
    return GitBlameParser.parse(result.standardOutput)
  }

  public func lineHistory(path: String, lines: ClosedRange<Int>, limit: Int) async throws
    -> [LineHistoryEntry]
  {
    let result = try await run(
      [
        "log", "-L", "\(lines.lowerBound),\(lines.upperBound):\(path)",
        "--format=\(LineHistoryParser.format)", "--max-count=\(limit)", "HEAD",
      ],
      timeout: .seconds(120)
    )
    return try LineHistoryParser.parse(result.standardOutput)
  }

  public func describe(_ oid: ObjectID) async throws -> CommitDescription {
    // Each fails when no tag qualifies, which only means "none".
    async let nearest = describeOutput(["describe", "--tags", "--long", "--abbrev=7", oid.rawValue])
    async let containing = describeOutput(["describe", "--tags", "--contains", oid.rawValue])
    let parsed = await nearest.flatMap(CommitDescription.parseNearest)
    return CommitDescription(
      nearestTag: parsed?.tag,
      commitsSinceTag: parsed?.distance ?? 0,
      firstContainingTag: await containing.flatMap(CommitDescription.parseContaining)
    )
  }

  private func describeOutput(_ arguments: [String]) async -> String? {
    try? await run(arguments, timeout: .seconds(20)).standardOutputText
  }

  public func searchCode(_ query: CodeSearchQuery, limit: Int) async throws -> CodeSearchResult {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: query.arguments,
      timeout: .seconds(60)
    )
    let result = try await runner.run(command)
    // `git grep` exits 1 when nothing matches.
    if result.exitCode == 1 { return CodeSearchResult(matches: [], isTruncated: false) }
    return CodeSearchResult.parse(
      try result.checkSuccess(of: command).standardOutput,
      revision: query.revision,
      limit: limit
    )
  }

  public func commitDetail(_ oid: ObjectID, options: DiffOptions) async throws -> CommitDetail {
    let metadata = try await run([
      "log", "-1", "-z", "--format=\(GitLogParser.logFormat)", oid.rawValue, "--",
    ])
    guard let commit = try GitLogParser.parse(metadata.standardOutput).first else {
      throw CommandError(
        kind: .launchFailed(reason: "no such commit \(oid.rawValue)"),
        command: GitCommand.make(git: git, repository: repositoryRoot, arguments: [])
      )
    }

    let message = try await run(["log", "-1", "--format=%B", oid.rawValue, "--"])
    // Verification shells out to gpg/ssh-keygen, so it only runs for the one
    // commit being inspected. A missing or broken signing tool must not hide
    // the rest of the detail.
    let signature = try? await run(
      ["log", "-1", "--format=\(GitSignatureParser.signatureFormat)", oid.rawValue, "--"]
    )

    // First-parent patch; `diff-tree` prints nothing for merges, so diff
    // against parent 1 explicitly. Root commits use --root.
    let patchArguments =
      if let firstParent = commit.parents.first {
        ["diff", "--patch", "--find-renames"] + options.arguments
          + ["\(firstParent.rawValue)..\(oid.rawValue)", "--"]
      } else {
        ["diff-tree", "--patch", "--root", "--find-renames"] + options.arguments
          + [oid.rawValue, "--"]
      }
    let patch = try await run(patchArguments)

    return CommitDetail(
      commit: commit,
      fullMessage: message.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines),
      diffs: try GitDiffParser.parse(patch.standardOutput),
      signature: signature.flatMap { GitSignatureParser.parse($0.standardOutputText) }
    )
  }
}
