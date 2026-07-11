public import Foundation

/// `GitClient` backed by the system git CLI.
///
/// One actor per repository: git's index lock makes concurrent mutation
/// pointless, so serialization here is the boring correct choice.
public actor SystemGitClient: GitClient {
  public nonisolated let repositoryRoot: URL
  private let git: URL
  private let runner: any CommandRunning

  public init(repositoryRoot: URL, git: URL, runner: any CommandRunning) {
    self.repositoryRoot = repositoryRoot
    self.git = git
    self.runner = runner
  }

  /// Resolves the repository root containing `url` (`git rev-parse
  /// --show-toplevel`), or nil when `url` is not inside a work tree.
  public static func repositoryRoot(
    containing url: URL,
    git: URL,
    runner: any CommandRunning
  ) async -> URL? {
    let command = GitCommand.make(
      git: git,
      repository: url,
      arguments: ["rev-parse", "--show-toplevel"],
      timeout: .seconds(10)
    )
    guard let result = try? await runner.run(command), result.isSuccess else { return nil }
    let path = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return nil }
    return URL(filePath: path)
  }

  // MARK: - GitClient

  public func status() async throws -> WorkingTreeStatus {
    let result = try await run(["status", "--porcelain=v2", "--branch", "--show-stash", "-z"])
    return try GitStatusParser.parse(result.standardOutput)
  }

  public func branches() async throws -> [Branch] {
    let result = try await run([
      "for-each-ref", "refs/heads",
      "--sort=-committerdate",
      "--format=\(GitRefParser.branchFormat)",
    ])
    return try GitRefParser.parseBranches(result.standardOutput)
  }

  public func remotes() async throws -> [Remote] {
    let result = try await run(["remote", "-v"])
    return Self.parseRemotes(result.standardOutputText)
  }

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
    arguments.append(query.reference ?? "HEAD")
    arguments.append("--")
    let result = try await run(arguments)
    var commits = try GitLogParser.parse(result.standardOutput)
    let hasMore = commits.count > query.maxCount
    if hasMore {
      commits.removeLast()
    }
    return LogPage(commits: commits, hasMore: hasMore)
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
    let maxBytes = 2 * 1024 * 1024
    let data = try Data(contentsOf: url)

    // NUL in the head of the file → treat as binary, like git does.
    if data.prefix(8192).contains(0) {
      return FileDiff(path: path, kind: .added, isBinary: true)
    }
    let clipped = data.prefix(maxBytes)
    let text = String(decoding: clipped, as: UTF8.self)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
    let endsWithNewline = text.hasSuffix("\n")
    if endsWithNewline {
      lines = lines.dropLast()
    }

    var diffLines: [DiffLine] = []
    diffLines.reserveCapacity(lines.count + 1)
    for (index, line) in lines.enumerated() {
      diffLines.append(DiffLine(kind: .addition, text: String(line), newLine: index + 1))
    }
    if !endsWithNewline, !diffLines.isEmpty {
      diffLines.append(DiffLine(kind: .noNewlineMarker, text: "\\ No newline at end of file"))
    }
    let hunk = Hunk(
      header: "@@ -0,0 +1,\(lines.count) @@",
      oldStart: 0,
      oldCount: 0,
      newStart: 1,
      newCount: lines.count,
      lines: diffLines
    )
    return FileDiff(path: path, kind: .added, hunks: diffLines.isEmpty ? [] : [hunk])
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
      patch = try await run(["diff-tree", "--patch", "--root", "--find-renames", oid.rawValue, "--"])
    }

    return CommitDetail(
      commit: commit,
      fullMessage: message.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines),
      diffs: try GitDiffParser.parse(patch.standardOutput)
    )
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

  public func applyPatch(_ patch: String, reverse: Bool) async throws {
    var arguments = ["apply", "--cached", "--whitespace=nowarn"]
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

  public func checkout(branch: String) async throws {
    try await runVoid(["switch", branch])
  }

  public func createBranch(name: String, checkout: Bool) async throws {
    if checkout {
      try await runVoid(["switch", "-c", name])
    } else {
      try await runVoid(["branch", name])
    }
  }

  public func fetch() async throws {
    try await runVoid(["fetch", "--all", "--prune"], timeout: .seconds(300))
  }

  public func pull() async throws {
    try await runVoid(["pull"], timeout: .seconds(300))
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
        try await runVoid(
          ["push", "--set-upstream", "origin", "HEAD"] + (force ? ["--force-with-lease"] : []),
          timeout: .seconds(300)
        )
      } else {
        throw error
      }
    }
  }

  public func mergeBase(_ a: String, _ b: String) async throws -> ObjectID {
    let result = try await run(["merge-base", a, b])
    let text = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let oid = ObjectID(rawValue: text) else {
      throw CommandError(
        kind: .launchFailed(reason: "unexpected merge-base output"),
        command: GitCommand.make(git: git, repository: repositoryRoot, arguments: [])
      )
    }
    return oid
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

  public func diff(from: String, to: String) async throws -> [FileDiff] {
    let result = try await run(["diff", "--patch", "--find-renames", "\(from)..\(to)", "--"])
    return try GitDiffParser.parse(result.standardOutput)
  }

  public func diffText(from: String, to: String) async throws -> String {
    let result = try await run(["diff", "--patch", "--find-renames", "\(from)..\(to)", "--"])
    return result.standardOutputText
  }

  public func stagedDiffText() async throws -> String {
    let result = try await run(["diff", "--cached", "--patch", "--find-renames", "--"])
    return result.standardOutputText
  }

  // MARK: - Stashes

  public func stashes() async throws -> [Stash] {
    let result = try await run(["stash", "list", "-z", "--format=%gd%x1f%gs"])
    let text = String(decoding: result.standardOutput, as: UTF8.self)
    return text.split(separator: "\0", omittingEmptySubsequences: true).compactMap { record in
      let fields = record.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
      guard
        fields.count == 2,
        let open = fields[0].firstIndex(of: "{"),
        let close = fields[0].firstIndex(of: "}"),
        open < close,
        let index = Int(fields[0][fields[0].index(after: open)..<close])
      else { return nil }
      return Stash(index: index, message: String(fields[1]))
    }
  }

  public func saveStash(message: String?, includeUntracked: Bool) async throws {
    var arguments = ["stash", "push"]
    if includeUntracked {
      arguments.append("--include-untracked")
    }
    if let message, !message.isEmpty {
      arguments.append(contentsOf: ["-m", message])
    }
    try await runVoid(arguments)
  }

  public func applyStash(_ stash: Stash, pop: Bool) async throws {
    try await runVoid(["stash", pop ? "pop" : "apply", stash.reference])
  }

  public func dropStash(_ stash: Stash) async throws {
    try await runVoid(["stash", "drop", stash.reference])
  }

  // MARK: - Helpers

  private func run(_ arguments: [String], timeout: Duration? = .seconds(30)) async throws -> CommandResult {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: arguments,
      timeout: timeout
    )
    return try await runner.run(command).checkSuccess(of: command)
  }

  private func runVoid(
    _ arguments: [String],
    standardInput: Data? = nil,
    timeout: Duration? = .seconds(30)
  ) async throws {
    var command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: arguments,
      timeout: timeout
    )
    command.standardInput = standardInput
    _ = try await runner.run(command).checkSuccess(of: command)
  }

  /// `git remote -v` → `name\turl (fetch)` / `name\turl (push)` lines.
  static func parseRemotes(_ text: String) -> [Remote] {
    var byName: [String: Remote] = [:]
    var order: [String] = []
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: "\t", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let name = String(parts[0])
      let rest = parts[1]
      let isPush = rest.hasSuffix(" (push)")
      let url = String(rest.replacingOccurrences(of: " (fetch)", with: "").replacingOccurrences(of: " (push)", with: ""))
      if var existing = byName[name] {
        if isPush, existing.fetchURL != url { existing.pushURL = url }
        byName[name] = existing
      } else {
        byName[name] = Remote(name: name, fetchURL: url)
        order.append(name)
      }
    }
    return order.compactMap { byName[$0] }
  }
}
