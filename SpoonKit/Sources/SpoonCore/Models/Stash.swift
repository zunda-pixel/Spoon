public import MemberwiseInit

/// One entry from `git stash list`.
@MemberwiseInit(.public)
public struct Stash: Sendable, Hashable, Identifiable {
  /// Position in the stash stack (`stash@{index}`).
  public var index: Int
  /// e.g. `WIP on main: 4ae2b1b subject` or a custom message.
  public var message: String

  public var id: Int { index }

  public var reference: String { "stash@{\(index)}" }
}
