public import MemberwiseInit

/// An in-progress `git bisect`, read from the `refs/bisect/*` refs.
@MemberwiseInit(.public)
public struct BisectState: Sendable, Hashable {
  /// The commit known to contain the problem (`refs/bisect/bad`).
  public var badOID: ObjectID? = nil
  /// Commits known to be free of it (`refs/bisect/good-*`).
  public var goodOIDs: [ObjectID] = []
  /// Commits skipped as untestable (`refs/bisect/skip-*`).
  public var skippedOIDs: [ObjectID] = []
  /// Commits still between the good and bad marks; `nil` until both exist.
  public var remainingCount: Int? = nil

  /// About how many more marks git needs (log2 of the remaining range).
  public var estimatedStepsLeft: Int? {
    guard let remainingCount, remainingCount > 0 else { return nil }
    var steps = 0
    var range = remainingCount
    while range > 1 {
      range = (range + 1) / 2
      steps += 1
    }
    return steps
  }
}

/// A verdict for the commit under test.
public enum BisectMark: String, Sendable, Hashable {
  case good
  case bad
  case skip
}

/// What git reported after a mark.
public enum BisectProgress: Sendable, Hashable {
  /// Git checked out another commit to test.
  case testing(ObjectID?)
  /// The first bad commit was found. With `--reset-when-found`, git has
  /// already ended the bisect and restored the original checkout.
  case found(ObjectID)
}
