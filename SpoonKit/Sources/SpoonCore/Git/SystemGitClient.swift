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

  /// Creates a repository at `destination` with the requested initial branch.
  public static func initialize(
    at destination: URL,
    initialBranch: String,
    git: URL,
    runner: any CommandRunning
  ) async throws {
    let command = GitCommand.make(
      git: git,
      repository: nil,
      arguments: ["init", "--initial-branch", initialBranch, destination.path],
      timeout: .seconds(30)
    )
    _ = try await runner.run(command).checkSuccess(of: command)
  }

  /// Clones `remoteURL` into `destination`, reporting git's `--progress`
  /// lines (they arrive on stderr, `\r`-separated; the latest line wins).
  public static func clone(
    from remoteURL: String,
    to destination: URL,
    options: CloneOptions = .standard,
    git: URL,
    runner: any CommandRunning,
    progress: @escaping @Sendable (String) -> Void
  ) async throws {
    let command = GitCommand.make(
      git: git,
      repository: nil,
      arguments: options.cloneArguments() + [remoteURL, destination.path],
      timeout: .seconds(3600)
    )
    var stderr = Data()
    for try await event in runner.events(command) {
      switch event {
      case .standardError(let chunk):
        stderr.append(chunk)
        let text = String(decoding: chunk, as: UTF8.self)
        let lines = text.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
          progress(String(last))
        }
      case .standardOutput:
        break
      case .exited(let code):
        guard code == 0 else {
          throw CommandError(
            kind: .nonZeroExit,
            command: command,
            exitCode: code,
            standardErrorExcerpt: CommandError.excerpt(from: stderr)
          )
        }
      }
    }
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

  public func checkout(branch: String) async throws {
    try await runVoid(["switch", branch])
  }

  public func checkoutRevision(_ oid: ObjectID) async throws {
    try await runVoid(["switch", "--detach", oid.rawValue])
  }

  public func merge(branch: String, options: MergeOptions) async throws {
    try await runVoid(options.arguments(branch: branch), timeout: .seconds(120))
  }

  // MARK: - Tags

  public func tags() async throws -> [Tag] {
    let result = try await run([
      "for-each-ref", "refs/tags",
      "--sort=-creatordate",
      "--format=\(GitTagParser.tagFormat)",
    ])
    return try GitTagParser.parse(result.standardOutput)
  }

  public func createTag(name: String, at target: ObjectID?, message: String?) async throws {
    var arguments = ["tag"]
    if let message, !message.isEmpty {
      arguments.append(contentsOf: ["-a", "-m", message])
    }
    arguments.append(name)
    if let target {
      arguments.append(target.rawValue)
    }
    try await runVoid(arguments)
  }

  public func deleteTag(name: String) async throws {
    try await runVoid(["tag", "-d", name])
  }

  public func pushTag(name: String, to remoteName: String) async throws {
    try await runVoid(
      ["push", remoteName, "refs/tags/\(name)"],
      timeout: .seconds(300)
    )
  }

  public func pushAllTags(to remoteName: String) async throws {
    try await runVoid(["push", remoteName, "--tags"], timeout: .seconds(300))
  }

  public func deleteRemoteTag(name: String, from remoteName: String) async throws {
    try await runVoid(
      ["push", remoteName, "--delete", "refs/tags/\(name)"],
      timeout: .seconds(300)
    )
  }

  public func createBranch(name: String, from startPoint: String?, checkout: Bool) async throws {
    var arguments = checkout ? ["switch", "-c", name] : ["branch", name]
    if let startPoint {
      arguments.append(startPoint)
    }
    try await runVoid(arguments)
  }

  public func checkoutRemoteBranch(_ remoteBranch: String) async throws {
    try await runVoid(["switch", "--track", remoteBranch])
  }

  public func deleteBranch(name: String, force: Bool) async throws {
    try await runVoid(["branch", force ? "-D" : "-d", name])
  }

  public func renameBranch(from oldName: String, to newName: String) async throws {
    try await runVoid(["branch", "-m", oldName, newName])
  }

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

  public func sparseCheckoutPaths() async throws -> [String]? {
    guard
      let enabled = try? await run(["config", "--bool", "core.sparseCheckout"]),
      enabled.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    else { return nil }
    let result = try await run(["sparse-checkout", "list"])
    return result.standardOutputText
      .split(separator: "\n")
      .map(String.init)
  }

  public func setSparseCheckout(paths: [String]) async throws {
    guard !paths.isEmpty else { return }
    try await runVoid(["sparse-checkout", "set", "--cone", "--"] + paths)
  }

  public func disableSparseCheckout() async throws {
    try await runVoid(["sparse-checkout", "disable"])
  }

  // MARK: - Sequencer (rebase / cherry-pick / revert)

  public func interactiveRebase(_ plan: RebasePlan) async throws {
    let todoURL = FileManager.default.temporaryDirectory
      .appending(path: "spoon-rebase-todo-\(UUID().uuidString)")
    let rewordDirectory = FileManager.default.temporaryDirectory
      .appending(path: "spoon-rebase-messages-\(UUID().uuidString)")
    try Data(plan.todoFileContents().utf8).write(to: todoURL)
    try FileManager.default.createDirectory(at: rewordDirectory, withIntermediateDirectories: true)
    for (index, step) in plan.steps.enumerated() where step.action == .reword {
      guard let message = step.newMessage else { continue }
      try Data(message.utf8).write(to: rewordDirectory.appending(path: "\(index)"))
    }
    defer {
      try? FileManager.default.removeItem(at: todoURL)
      try? FileManager.default.removeItem(at: rewordDirectory)
    }

    var arguments = ["rebase", "--interactive"]
    if let base = plan.baseOID {
      arguments.append(base.rawValue)
    } else {
      arguments.append("--root")
    }
    // git runs the sequence editor via `sh -c '<editor> "$@"' …`, so both
    // paths are shell *expansions* — spaces in either path are safe. The
    // todo path travels in its own variable, never interpolated into code.
    try await runVoid(
      arguments,
      extraEnvironment: [
        "SPOON_REBASE_TODO": todoURL.path,
        "SPOON_REWORD_DIR": rewordDirectory.path,
        "GIT_SEQUENCE_EDITOR": #"cp -f "$SPOON_REBASE_TODO""#,
        "GIT_EDITOR": "true",
      ],
      timeout: .seconds(300)
    )
  }

  public func cherryPick(_ oid: ObjectID) async throws {
    try await runVoid(["cherry-pick", oid.rawValue], timeout: .seconds(120))
  }

  public func revert(_ oid: ObjectID) async throws {
    try await runVoid(["revert", "--no-edit", oid.rawValue], timeout: .seconds(120))
  }

  public func sequencerState() async throws -> SequencerState? {
    let result = try await run(
      [
        "rev-parse",
        "--git-path", "rebase-merge",
        "--git-path", "rebase-apply",
        "--git-path", "CHERRY_PICK_HEAD",
        "--git-path", "REVERT_HEAD",
        "--git-path", "MERGE_HEAD",
      ],
      timeout: .seconds(10)
    )
    let paths = result.standardOutputText
      .split(separator: "\n")
      .map { resolveGitPath(String($0)) }
    guard paths.count == 5 else { return nil }
    let exists = paths.map { FileManager.default.fileExists(atPath: $0.path) }
    // A conflicted rebase pick also writes CHERRY_PICK_HEAD, so rebase wins.
    if exists[0] || exists[1] {
      return rebaseState(directory: exists[0] ? paths[0] : paths[1])
    }
    if exists[2] {
      return SequencerState(kind: .cherryPick)
    }
    if exists[3] {
      return SequencerState(kind: .revert)
    }
    if exists[4] {
      return SequencerState(kind: .merge)
    }
    return nil
  }

  public func continueSequencer(_ kind: SequencerState.Kind) async throws {
    // A squash's combined-message editor can fire during --continue.
    try await runVoid(
      [Self.sequencerSubcommand(kind), "--continue"],
      extraEnvironment: ["GIT_EDITOR": "true"],
      timeout: .seconds(300)
    )
  }

  public func skipSequencer(_ kind: SequencerState.Kind) async throws {
    try await runVoid(
      [Self.sequencerSubcommand(kind), "--skip"],
      extraEnvironment: ["GIT_EDITOR": "true"],
      timeout: .seconds(300)
    )
  }

  public func abortSequencer(_ kind: SequencerState.Kind) async throws {
    try await runVoid([Self.sequencerSubcommand(kind), "--abort"], timeout: .seconds(120))
  }

  private static func sequencerSubcommand(_ kind: SequencerState.Kind) -> String {
    switch kind {
    case .rebase: "rebase"
    case .cherryPick: "cherry-pick"
    case .revert: "revert"
    case .merge: "merge"
    }
  }

  private nonisolated func resolveGitPath(_ path: String) -> URL {
    path.hasPrefix("/")
      ? URL(filePath: path)
      : repositoryRoot.appending(path: path)
  }

  private nonisolated func rebaseState(directory: URL) -> SequencerState {
    func read(_ name: String) -> String? {
      guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
      return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var branch = read("head-name")
    if let name = branch, name.hasPrefix("refs/heads/") {
      branch = String(name.dropFirst("refs/heads/".count))
    }
    return SequencerState(
      kind: .rebase,
      branchName: branch,
      stoppedOID: read("stopped-sha").flatMap(ObjectID.init(rawValue:)),
      stepNumber: read("msgnum").flatMap(Int.init),
      stepCount: read("end").flatMap(Int.init)
    )
  }

  public func fetch() async throws {
    try await runVoid(["fetch", "--all", "--prune"], timeout: .seconds(300))
  }

  public func supportsBackfill() async -> Bool {
    guard let result = try? await run(["version"], timeout: .seconds(10)) else { return false }
    let fields = result.standardOutputText.split(whereSeparator: { !$0.isNumber && $0 != "." })
    guard let version = fields.first(where: { $0.contains(".") }) else { return false }
    let components = version.split(separator: ".").compactMap { Int($0) }
    guard components.count >= 2 else { return false }
    return components[0] > 2 || (components[0] == 2 && components[1] >= 49)
  }

  public func backfill() async throws {
    try await runVoid(["backfill"], timeout: .seconds(3600))
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

  public func stashDiffs(_ stash: Stash) async throws -> [FileDiff] {
    // `stash show` emits a regular unified diff; --include-untracked also
    // surfaces the untracked-files commit our saveStash records.
    let result = try await run([
      "stash", "show", "--include-untracked", "--patch", "--find-renames", stash.reference,
    ])
    return try GitDiffParser.parse(result.standardOutput)
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
    extraEnvironment: [String: String] = [:],
    timeout: Duration? = .seconds(30)
  ) async throws {
    var command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: arguments,
      extraEnvironment: extraEnvironment,
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
