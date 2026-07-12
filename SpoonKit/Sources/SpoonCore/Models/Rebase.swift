public import Foundation
public import MemberwiseInit

/// Why an interactive rebase cannot start from the requested commit.
public enum RebaseSetupError: LocalizedError, Sendable, Hashable {
  case workingTreeNotClean
  case detachedHead
  case sequencerActive
  case mergeInRange
  case rangeTooLarge

  public var errorDescription: String? {
    switch self {
    case .workingTreeNotClean:
      "Commit or stash your changes before rebasing."
    case .detachedHead:
      "Rebase requires a checked-out branch (HEAD is detached)."
    case .sequencerActive:
      "Another rebase, cherry-pick, or revert is already in progress."
    case .mergeInRange:
      "The selected range contains a merge commit, which Spoon cannot rebase yet."
    case .rangeTooLarge:
      "The selected range is too large to rebase (over 1,000 commits)."
    }
  }
}

/// A todo action for headless interactive rebase (v1 subset — reword and
/// fixup are deliberately left out until there is message-editing UI).
public enum RebaseAction: String, Sendable, Hashable, CaseIterable {
  case pick
  case squash
  case drop
  case edit
}

/// One line of the rebase todo list.
@MemberwiseInit(.public)
public struct RebaseStep: Sendable, Hashable, Identifiable {
  public var action: RebaseAction
  public var commit: Commit

  public var id: String { commit.id }
}

/// A complete headless `rebase -i` plan. `steps` are oldest-first — exactly
/// the todo-file order.
@MemberwiseInit(.public)
public struct RebasePlan: Sendable, Hashable {
  public var steps: [RebaseStep]
  /// Commit rebased onto (parent of the oldest step); `nil` means `--root`.
  public var baseOID: ObjectID?

  public enum ValidationError: Sendable, Hashable {
    /// No steps, or every step is a drop.
    case empty
    /// A squash has no earlier kept commit to fold into.
    case squashWithoutTarget
  }

  public var validationError: ValidationError? {
    guard steps.contains(where: { $0.action != .drop }) else { return .empty }
    var hasTarget = false
    for step in steps {
      switch step.action {
      case .squash:
        if !hasTarget { return .squashWithoutTarget }
      case .pick, .edit:
        hasTarget = true
      case .drop:
        break
      }
    }
    return nil
  }

  /// `<action> <full-oid> <subject>` per step. Drops are explicit lines, not
  /// omissions, so `rebase.missingCommitsCheck = error` setups keep working.
  public func todoFileContents() -> String {
    steps
      .map { "\($0.action.rawValue) \($0.commit.oid.rawValue) \($0.commit.subject)\n" }
      .joined()
  }
}
