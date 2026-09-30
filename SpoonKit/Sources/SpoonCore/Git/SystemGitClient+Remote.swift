import Foundation

extension SystemGitClient {

  public func remotes() async throws -> [Remote] {
    let result = try await run(["remote", "-v"])
    return GitRemoteParser.parse(result.standardOutputText)
  }

  public func remoteBranches(of remoteName: String) async throws -> [Branch] {
    let result = try await run([
      "for-each-ref", "refs/remotes/\(remoteName)",
      "--sort=-committerdate",
      "--format=\(GitRefParser.branchFormat)",
    ])
    // HEAD/upstream fields are empty for remote refs; the parser maps them
    // to isCurrent=false / upstream=nil, which is exactly right here.
    return try GitRefParser.parseBranches(result.standardOutput)
  }

  public func addRemote(name: String, url: String) async throws {
    try await runVoid(["remote", "add", name, url])
  }

  public func setRemoteURL(name: String, fetchURL: String, pushURL: String?) async throws {
    try await runVoid(["remote", "set-url", name, fetchURL])
    try await runVoid(["remote", "set-url", "--push", name, pushURL ?? fetchURL])
  }

  public func removeRemote(name: String) async throws {
    try await runVoid(["remote", "remove", name])
  }

  public func renameRemoteBranch(
    remoteName: String,
    from oldName: String,
    to newName: String
  ) async throws {
    try await runVoid(
      [
        "push",
        remoteName,
        "refs/remotes/\(remoteName)/\(oldName):refs/heads/\(newName)",
      ],
      timeout: .seconds(300)
    )
    try await deleteRemoteBranch(name: oldName, from: remoteName)
  }

  public func deleteRemoteBranch(name: String, from remoteName: String) async throws {
    do {
      try await runVoid(
        ["push", remoteName, "--delete", name],
        timeout: .seconds(300)
      )
    } catch let error as CommandError where Self.isMissingRemoteRef(error) {
      // Deleting an already-removed remote branch is idempotent. The remote
      // state may have changed after the branch list was loaded, so Git can
      // report this as a failed push even though the requested end state is
      // already true.
    }
  }

  private static func isMissingRemoteRef(_ error: CommandError) -> Bool {
    let message = error.standardErrorExcerpt.lowercased()
    return message.contains("remote ref does not exist")
      || message.contains("dst ref not found")
      || (message.contains("unable to delete") && message.contains("not found"))
  }

  public func publishBranch(_ branch: String, to remoteName: String) async throws {
    try await runVoid(
      ["push", "--set-upstream", remoteName, "refs/heads/\(branch):refs/heads/\(branch)"],
      timeout: .seconds(300)
    )
  }

  public func fetch() async throws {
    try await runVoid(["fetch", "--all", "--prune"], timeout: .seconds(300))
  }

  public func isShallowRepository() async throws -> Bool {
    let result = try await run(["rev-parse", "--is-shallow-repository"], timeout: .seconds(10))
    return result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
  }

  public func deepenHistory(_ depth: HistoryDepth) async throws {
    // A full history can be large; allow a long download.
    try await runVoid(["fetch"] + depth.arguments, timeout: .seconds(3600))
  }

  public func backfill() async throws {
    try await runVoid(["backfill"], timeout: .seconds(3600))
  }

  public func missingObjectIDs() async throws -> [ObjectID] {
    let result = try await run(
      ["rev-list", "--objects", "--missing=print", "--missing-only", "HEAD"],
      timeout: .seconds(300)
    )
    return result.standardOutputText.split(whereSeparator: \.isNewline).compactMap {
      ObjectID(rawValue: String($0))
    }
  }

  public func remoteObjectSizes(
    of objects: [ObjectID],
    from remoteName: String
  ) async throws -> [ObjectID: Int] {
    guard !objects.isEmpty else { return [:] }
    // Chunk so each protocol request and stdin line stays modest.
    let commands = stride(from: 0, to: objects.count, by: 500).map { start in
      let chunk = objects[start..<min(start + 500, objects.count)]
      return "remote-object-info \(remoteName) "
        + chunk.map(\.rawValue).joined(separator: " ") + "\n"
    }
    let result = try await run(
      ["cat-file", "--batch-command=%(objectname) %(objectsize)"],
      standardInput: Data(commands.joined().utf8),
      timeout: .seconds(300)
    )
    var sizes: [ObjectID: Int] = [:]
    for line in result.standardOutputText.split(whereSeparator: \.isNewline) {
      let fields = line.split(separator: " ")
      guard
        fields.count == 2,
        let oid = ObjectID(rawValue: String(fields[0])),
        let size = Int(fields[1])
      else { continue }
      sizes[oid] = size
    }
    return sizes
  }

  public func partialCloneRemote() async throws -> String? {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["config", "--get", "extensions.partialClone"],
      timeout: .seconds(10)
    )
    let result = try await runner.run(command)
    // `git config --get` exits 1 when the key is unset.
    if result.exitCode == 1 { return nil }
    let remote = try result.checkSuccess(of: command).standardOutputText
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return remote.isEmpty ? nil : remote
  }

  public func dropLargeBlobs(largerThan byteLimit: Int) async throws {
    try await runVoid(
      [
        "repack", "-a", "-d", "--drop-filtered",
        "--filter=blob:limit=\(byteLimit)",
        // Bitmaps assume one pack holding every object, which a filter breaks.
        "--no-write-bitmap-index",
      ],
      timeout: .seconds(3600)
    )
  }

  public func pull(_ options: PullOptions) async throws {
    try await runVoid(["pull"] + options.arguments, timeout: .seconds(300))
  }

  public func push(force: Bool) async throws {
    var arguments = ["push"]
    if force {
      arguments.append("--force-with-lease")
    }
    do {
      try await runVoid(arguments, timeout: .seconds(300))
    } catch let error as CommandError {
      // First push of a new branch: set upstream and retry once.
      if error.standardErrorExcerpt.contains("--set-upstream") {
        var upstreamArguments = ["push"]
        if force {
          upstreamArguments.append("--force-with-lease")
        }
        upstreamArguments.append(contentsOf: ["--set-upstream", "origin", "HEAD"])
        try await runVoid(
          upstreamArguments,
          timeout: .seconds(300)
        )
      } else {
        throw error
      }
    }
  }

  /// `git remote -v` → `name\turl (fetch)` / `name\turl (push)` lines.
  static func parseRemotes(_ text: String) -> [Remote] {
    GitRemoteParser.parse(text)
  }
}
