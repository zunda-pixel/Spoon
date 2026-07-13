import Foundation

extension SystemGitClient {

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
}
