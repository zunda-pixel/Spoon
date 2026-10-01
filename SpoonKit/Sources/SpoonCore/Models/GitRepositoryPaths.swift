public import Foundation
public import MemberwiseInit

/// Absolute locations of one checkout's git metadata.
@MemberwiseInit(.public)
public struct GitRepositoryPaths: Sendable, Hashable {
  /// This checkout's git directory (`.git`, or `.git/worktrees/<name>` for a
  /// linked worktree): HEAD, the index, and in-progress operation state.
  public var gitDirectory: URL
  /// The directory shared by every worktree: objects, refs, and config.
  public var commonDirectory: URL
}

/// Git printed repository paths Spoon could not interpret.
public enum GitRepositoryPathsError: LocalizedError, Sendable, Hashable {
  case unrecognizedOutput

  public var errorDescription: String? {
    "Git reported repository paths in an unexpected format."
  }
}
