public import Foundation
public import MemberwiseInit

/// One commit pairing from `git range-diff`.
@MemberwiseInit(.public)
public struct RangeDiffEntry: Sendable, Hashable, Identifiable {
  public enum Relation: Sendable, Hashable {
    /// The commit is unchanged (`=`).
    case unchanged
    /// The commit exists on both sides but its patch changed (`!`).
    case changed
    /// Only in the old range (`<`).
    case removed
    /// Only in the new range (`>`).
    case added
  }

  public var relation: Relation
  /// 1-based position in the old range; `nil` when added.
  public var oldPosition: Int?
  public var oldOID: String?
  /// 1-based position in the new range; `nil` when removed.
  public var newPosition: Int?
  public var newOID: String?
  public var subject: String
  /// For `.changed`: the diff between the two patches, one line each.
  public var patchDiff: [String] = []

  public var id: String { "\(oldOID ?? "-")>\(newOID ?? "-")" }
}

/// Which earlier version of a branch to compare the current one with.
public enum BranchVersionBaseline: Sendable, Hashable {
  /// Where the branch pointed before its last move (reflog `@{1}`), such as
  /// before a rebase or amend.
  case previousPosition
  /// The branch's upstream, such as before a force push.
  case upstream
}

/// Why two versions of a branch could not be compared.
public enum BranchVersionComparisonError: LocalizedError, Sendable, Hashable {
  case noPreviousPosition(branch: String)
  case noUpstream(branch: String)

  public var errorDescription: String? {
    switch self {
    case .noPreviousPosition(let branch):
      "“\(branch)” has no earlier position in its reflog."
    case .noUpstream(let branch):
      "“\(branch)” has no upstream branch to compare with."
    }
  }
}
