/// The outcome of merging a branch into HEAD, computed without touching the
/// index or working tree (`git merge-tree --write-tree`).
public struct MergePreview: Sendable, Hashable {
  /// Paths that would conflict with Git's default merge strategy; empty
  /// when the merge is clean.
  public var conflictedPaths: [String]

  public init(conflictedPaths: [String]) {
    self.conflictedPaths = conflictedPaths
  }

  public var isClean: Bool { conflictedPaths.isEmpty }
}
