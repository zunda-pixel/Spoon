public import MemberwiseInit

/// An in-progress rebase / cherry-pick / revert, detected from `.git` state
/// files. Whether the pause is a conflict or an `edit` stop is not encoded
/// here — check the working-tree status for conflicted entries.
@MemberwiseInit(.public)
public struct SequencerState: Sendable, Hashable {
  public enum Kind: Sendable, Hashable {
    case rebase
    case cherryPick
    case revert
  }

  public var kind: Kind
  /// Branch being rebased (rebase only).
  public var branchName: String? = nil
  /// Commit the rebase stopped at (rebase only).
  public var stoppedOID: ObjectID? = nil
  /// 1-based progress through the todo list (rebase only).
  public var stepNumber: Int? = nil
  public var stepCount: Int? = nil
}
