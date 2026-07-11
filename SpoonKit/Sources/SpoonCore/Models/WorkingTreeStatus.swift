public import MemberwiseInit

/// One path in `git status` output.
@MemberwiseInit(.public)
public struct FileStatusEntry: Sendable, Hashable, Identifiable {
  public enum Change: Character, Sendable, Hashable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case typeChanged = "T"
  }

  public enum Conflict: Sendable, Hashable {
    case bothModified
    case bothAdded
    case bothDeleted
    case addedByUs
    case addedByThem
    case deletedByUs
    case deletedByThem
  }

  public var path: String
  /// Original path for renames/copies.
  public var originalPath: String? = nil
  /// Index vs HEAD.
  public var staged: Change? = nil
  /// Working tree vs index.
  public var unstaged: Change? = nil
  public var isUntracked: Bool = false
  public var isIgnored: Bool = false
  public var conflict: Conflict? = nil

  public var id: String { path }
}

/// Snapshot of `git status --porcelain=v2 --branch`.
@MemberwiseInit(.public)
public struct WorkingTreeStatus: Sendable, Hashable {
  /// `nil` on an unborn branch (no commits yet).
  public var headOID: ObjectID? = nil
  /// Current branch short name; `nil` when HEAD is detached.
  public var headBranch: String? = nil
  public var upstream: String? = nil
  public var ahead: Int? = nil
  public var behind: Int? = nil
  public var entries: [FileStatusEntry] = []

  public var stagedEntries: [FileStatusEntry] {
    entries.filter { $0.staged != nil && $0.conflict == nil }
  }

  public var unstagedEntries: [FileStatusEntry] {
    entries.filter { $0.unstaged != nil && $0.conflict == nil && !$0.isUntracked }
  }

  public var untrackedEntries: [FileStatusEntry] {
    entries.filter(\.isUntracked)
  }

  public var conflictedEntries: [FileStatusEntry] {
    entries.filter { $0.conflict != nil }
  }

  public var isClean: Bool {
    entries.allSatisfy(\.isIgnored)
  }
}
