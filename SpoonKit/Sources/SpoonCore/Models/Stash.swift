/// One entry from `git stash list`.
public struct Stash: Sendable, Hashable, Identifiable {
  /// Position in the stash stack (`stash@{index}`).
  public var index: Int
  /// Commit stored at this stash entry.
  public var target: ObjectID
  /// Git's implementation-only index/untracked snapshot commits.
  public var helperCommitOIDs: [ObjectID]
  /// e.g. `WIP on main: 4ae2b1b subject` or a custom message.
  public var message: String

  public init(
    index: Int,
    target: ObjectID,
    helperCommitOIDs: [ObjectID] = [],
    message: String
  ) {
    self.index = index
    self.target = target
    self.helperCommitOIDs = helperCommitOIDs
    self.message = message
  }

  public var id: Int { index }

  public var reference: String { "stash@{\(index)}" }
}
