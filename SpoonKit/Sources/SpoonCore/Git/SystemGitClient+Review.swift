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
}
