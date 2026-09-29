extension RepositoryModel {
  public var isBisecting: Bool { bisectState != nil }

  /// Whether a bisect can start with `commit` as the known-good end and the
  /// checked-out commit as the known-bad end.
  public func canStartBisect(from commit: Commit) -> Bool {
    guard let head = status?.headOID, !isBisecting, !isSequencing, commit.oid != head else {
      return false
    }
    return canRevert(commit.oid)
  }

  /// Starts bisecting between HEAD (bad) and `good`.
  public func startBisect(good: ObjectID) async {
    guard let head = status?.headOID else { return }
    bisectResult = nil
    await runBisect { try await $0.startBisect(bad: head, good: good) }
  }

  /// Marks `revision` (the commit under test when `nil`).
  public func markBisect(_ mark: BisectMark, revision: ObjectID? = nil) async {
    await runBisect { try await $0.markBisect(mark, revision: revision) }
  }

  public func resetBisect() async {
    await perform { try await $0.resetBisect() }
  }

  public func dismissBisectResult() {
    bisectResult = nil
  }

  private func runBisect(_ step: (any GitClient) async throws -> BisectProgress) async {
    var progress: BisectProgress?
    await perform { progress = try await step($0) }
    if case .found(let culprit) = progress {
      bisectResult = culprit
    }
  }
}
