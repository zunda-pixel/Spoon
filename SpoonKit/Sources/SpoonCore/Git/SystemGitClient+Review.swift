import Foundation

extension SystemGitClient {

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

  public func rangeDiff(
    oldBase: ObjectID, oldTip: ObjectID, newBase: ObjectID, newTip: ObjectID
  ) async throws -> [RangeDiffEntry] {
    let result = try await run(
      [
        "range-diff", "--no-color",
        "\(oldBase.rawValue)..\(oldTip.rawValue)", "\(newBase.rawValue)..\(newTip.rawValue)",
      ],
      timeout: .seconds(120)
    )
    return GitRangeDiffParser.parse(result.standardOutputText)
  }

  public func previousTip(of reference: String) async throws -> ObjectID? {
    let command = GitCommand.make(
      git: git,
      repository: repositoryRoot,
      arguments: ["rev-parse", "--verify", "--quiet", "\(reference)@{1}^{commit}"],
      timeout: .seconds(10)
    )
    let result = try await runner.run(command)
    // `--verify --quiet` exits 1 without output when there is no such entry.
    guard result.exitCode == 0 else { return nil }
    return ObjectID(
      rawValue: result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
