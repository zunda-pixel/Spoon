import Foundation

extension SystemGitClient {

  // MARK: - Bisect

  public func bisectState() async throws -> BisectState? {
    let marker = try await run(
      ["rev-parse", "--path-format=absolute", "--git-path", "BISECT_START"],
      timeout: .seconds(10)
    )
    let markerPath = marker.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !markerPath.isEmpty, FileManager.default.fileExists(atPath: markerPath) else {
      return nil
    }

    let refs = try await run(
      ["for-each-ref", "refs/bisect", "--format=%(refname)%09%(objectname)"],
      timeout: .seconds(10)
    )
    var state = GitBisectParser.parseRefs(refs.standardOutputText)
    if let bad = state.badOID, !state.goodOIDs.isEmpty {
      let count = try? await run(
        ["rev-list", "--count", bad.rawValue, "--not"] + state.goodOIDs.map(\.rawValue),
        timeout: .seconds(30)
      )
      // The count includes the known-bad tip itself.
      state.remainingCount = count.flatMap {
        Int($0.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines))
      }.map { max($0 - 1, 0) }
    }
    return state
  }

  public func startBisect(bad: ObjectID, good: ObjectID) async throws -> BisectProgress {
    var arguments = ["bisect", "start"]
    if await capabilities().supportsBisectResetWhenFound {
      arguments.append("--reset-when-found=original")
    }
    arguments.append(contentsOf: [bad.rawValue, good.rawValue, "--"])
    let result = try await run(arguments, timeout: .seconds(300))
    return GitBisectParser.parseProgress(result.standardOutputText)
  }

  public func markBisect(_ mark: BisectMark, revision: ObjectID?) async throws -> BisectProgress {
    var arguments = ["bisect", mark.rawValue]
    if let revision {
      arguments.append(revision.rawValue)
    }
    let result = try await run(arguments, timeout: .seconds(300))
    return GitBisectParser.parseProgress(result.standardOutputText)
  }

  public func resetBisect() async throws {
    try await runVoid(["bisect", "reset"], timeout: .seconds(120))
  }
}
