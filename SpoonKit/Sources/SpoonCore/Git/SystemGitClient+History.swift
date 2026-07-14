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
    if query.allReferences {
      arguments.append("--all")
    }
    if let reference = query.reference {
      arguments.append(reference)
    } else if !query.allReferences {
      arguments.append("HEAD")
    }
    arguments.append(contentsOf: query.additionalRevisions.map(\.rawValue))
    arguments.append("--")
    if let path = query.path {
      arguments.append(path)
    }
    let result = try await run(arguments)
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

  public func commitDetail(_ oid: ObjectID) async throws -> CommitDetail {
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

    // First-parent patch; `diff-tree` prints nothing for merges, so diff
    // against parent 1 explicitly. Root commits use --root.
    let patch: CommandResult
    if let firstParent = commit.parents.first {
      patch = try await run([
        "diff", "--patch", "--find-renames", "\(firstParent.rawValue)..\(oid.rawValue)", "--",
      ])
    } else {
      patch = try await run([
        "diff-tree", "--patch", "--root", "--find-renames", oid.rawValue, "--",
      ])
    }

    return CommitDetail(
      commit: commit,
      fullMessage: message.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines),
      diffs: try GitDiffParser.parse(patch.standardOutput)
    )
  }
}
