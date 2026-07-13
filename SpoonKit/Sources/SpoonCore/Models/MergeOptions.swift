/// Options controlling how `git merge` integrates a branch.
public struct MergeOptions: Sendable, Equatable {
  public enum CommitMode: String, Sendable, Hashable, CaseIterable {
    /// Let git fast-forward when possible and create a merge commit otherwise.
    case automatic
    /// Refuse the merge unless it can be fast-forwarded.
    case fastForwardOnly
    /// Always create a merge commit, even when fast-forwarding is possible.
    case createMergeCommit
    /// Stage the combined changes without creating a commit.
    case squash
  }

  public enum Strategy: String, Sendable, Hashable, CaseIterable {
    case automatic
    case ort
    case recursive
    case resolve
    case octopus
    case ours
    case subtree
  }

  public enum ConflictPreference: String, Sendable, Hashable, CaseIterable {
    case automatic
    case ours
    case theirs
  }

  public var commitMode: CommitMode
  public var strategy: Strategy
  public var conflictPreference: ConflictPreference

  public static let standard = MergeOptions()

  public init(
    commitMode: CommitMode = .automatic,
    strategy: Strategy = .automatic,
    conflictPreference: ConflictPreference = .automatic
  ) {
    self.commitMode = commitMode
    self.strategy = strategy
    self.conflictPreference = conflictPreference
  }

  /// Complete argv beginning with `merge` and ending with the source branch.
  func arguments(branch: String) -> [String] {
    var arguments = ["merge"]
    switch commitMode {
    case .automatic:
      arguments.append("--no-edit")
    case .fastForwardOnly:
      arguments.append("--ff-only")
    case .createMergeCommit:
      arguments.append(contentsOf: ["--no-ff", "--no-edit"])
    case .squash:
      arguments.append("--squash")
    }
    if strategy != .automatic {
      arguments.append("--strategy=\(strategy.rawValue)")
    }
    if conflictPreference != .automatic, strategy != .ours {
      arguments.append("--strategy-option=\(conflictPreference.rawValue)")
    }
    arguments.append(branch)
    return arguments
  }
}
