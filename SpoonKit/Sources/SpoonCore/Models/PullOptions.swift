/// How `git pull` integrates the upstream branch.
public struct PullOptions: Sendable, Hashable {
  public enum Strategy: String, Sendable, Hashable, CaseIterable {
    /// Whatever the repository's `pull.rebase` / `pull.ff` config says.
    case configured
    /// Replay local commits on top of the upstream (`--rebase`).
    case rebase
    /// Create a merge commit when the branches diverged (`--no-rebase`).
    case merge
    /// Refuse unless the branch can simply move forward (`--ff-only`).
    case fastForwardOnly
  }

  public var strategy: Strategy
  /// Stash local changes before pulling and reapply them afterwards.
  public var autostash: Bool

  public init(strategy: Strategy = .configured, autostash: Bool = false) {
    self.strategy = strategy
    self.autostash = autostash
  }

  /// `git pull` arguments after `pull`.
  var arguments: [String] {
    var arguments: [String] =
      switch strategy {
      case .configured: []
      case .rebase: ["--rebase"]
      case .merge: ["--no-rebase"]
      case .fastForwardOnly: ["--ff-only"]
      }
    if autostash {
      arguments.append("--autostash")
    }
    return arguments
  }
}
