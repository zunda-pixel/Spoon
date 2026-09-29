public import Foundation
public import MemberwiseInit

/// One entry from `git worktree list --porcelain`.
@MemberwiseInit(.public)
public struct Worktree: Sendable, Hashable, Identifiable {
  /// Absolute path of the worktree root.
  public var path: URL
  /// Checked-out branch short name; `nil` when detached or bare.
  public var branch: String?
  public var headOID: ObjectID?
  /// The main worktree (the repository itself; listed first by git).
  public var isMain: Bool
  /// Locked against pruning, moving, and removal (`git worktree lock`);
  /// the reason is empty when none was given.
  public var lockReason: String? = nil
  /// Why git would prune it, typically that its folder no longer exists.
  public var prunableReason: String? = nil

  public var isLocked: Bool { lockReason != nil }
  public var isPrunable: Bool { prunableReason != nil }

  public var id: String { path.path }

  public var name: String { path.lastPathComponent }
}
