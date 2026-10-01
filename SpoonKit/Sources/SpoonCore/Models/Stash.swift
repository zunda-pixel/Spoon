import Foundation
public import MemberwiseInit

/// One entry from `git stash list`.
@MemberwiseInit(.public)
public struct Stash: Sendable, Hashable, Identifiable {
  /// Position in the stash stack (`stash@{index}`).
  public var index: Int
  /// Commit stored at this stash entry.
  public var target: ObjectID
  /// Git's implementation-only index/untracked snapshot commits.
  public var helperCommitOIDs: [ObjectID] = []
  /// e.g. `WIP on main: 4ae2b1b subject` or a custom message.
  public var message: String

  public var id: Int { index }

  public var reference: String { "stash@{\(index)}" }
}

/// What `git stash push` saves.
@MemberwiseInit(.public)
public struct StashSaveOptions: Sendable, Hashable {
  public enum Scope: Sendable, Hashable {
    /// Staged and unstaged changes; both are removed from the working tree.
    case allChanges
    /// Only the staged changes (`--staged`); unstaged edits stay in place.
    case stagedOnly
    /// Everything, but the staged changes also stay in the index and
    /// working tree (`--keep-index`).
    case keepingIndex
  }

  public var message: String? = nil
  public var scope: Scope = .allChanges
  /// Also stash untracked files. Not available with `.stagedOnly`.
  public var includeUntracked: Bool = false
  /// Limits the stash to these paths; empty means every change.
  public var paths: [String] = []

  /// `git stash push` arguments after `push`.
  var arguments: [String] {
    var arguments: [String] = []
    switch scope {
    case .allChanges: break
    case .stagedOnly: arguments.append("--staged")
    case .keepingIndex: arguments.append("--keep-index")
    }
    if includeUntracked, scope != .stagedOnly {
      arguments.append("--include-untracked")
    }
    if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
      arguments.append(contentsOf: ["-m", message])
    }
    if !paths.isEmpty {
      arguments.append("--")
      arguments.append(contentsOf: paths)
    }
    return arguments
  }
}
