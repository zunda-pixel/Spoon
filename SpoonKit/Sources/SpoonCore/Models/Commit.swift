public import Foundation
public import MemberwiseInit

/// One commit from `git log`.
@MemberwiseInit(.public)
public struct Commit: Sendable, Hashable, Identifiable {
  public var oid: ObjectID
  public var parents: [ObjectID]
  public var subject: String
  public var authorName: String
  public var authorEmail: String
  public var authoredAt: Date
  public var committedAt: Date

  public var id: String { oid.rawValue }

  public var isMerge: Bool { parents.count > 1 }
}

/// A history filter: commits whose message, author, or code changes match.
@MemberwiseInit(.public)
public struct HistorySearch: Sendable, Hashable {
  public enum Field: String, Sendable, Hashable, CaseIterable {
    /// Commit message (`--grep`), case-insensitive.
    case message
    /// Author name or email (`--author`), case-insensitive.
    case author
    /// Commits that add or remove the text (`-S`, the "pickaxe").
    case code
    /// Commits whose added or removed lines match an extended regular
    /// expression (`-G`), case-insensitive. Unlike `code`, a line that only
    /// moves or changes around a match still counts.
    case changedLines
  }

  public var text: String
  public var field: Field

  /// The text is matched literally, except by `changedLines`, which takes
  /// a regular expression.
  var arguments: [String] {
    switch field {
    case .message: ["--regexp-ignore-case", "--fixed-strings", "--grep=\(text)"]
    case .author: ["--regexp-ignore-case", "--fixed-strings", "--author=\(text)"]
    case .code: ["-S\(text)"]
    case .changedLines: ["--regexp-ignore-case", "-G\(text)"]
    }
  }
}

/// Parameters for one `git log` page.
@MemberwiseInit(.public)
public struct LogQuery: Sendable, Hashable {
  /// Ref to walk from; `nil` means HEAD unless `allReferences` is enabled.
  public var reference: String? = nil
  /// Repository-relative path to follow; `nil` means all paths.
  public var path: String? = nil
  /// Keep following `path` across renames (`--follow`). Ignored without `path`.
  public var followRenames: Bool = false
  public var maxCount: Int = 500
  public var skip: Int = 0
  /// Include commits reachable from every ref.
  public var allReferences: Bool = false
  /// Extra commit tips to walk, such as detached worktree HEADs.
  public var additionalRevisions: [ObjectID] = []
  /// Explicit reference tips to walk when `allReferences` is false.
  public var references: [String] = []
  /// References to subtract from an `--all` walk.
  public var excludedReferences: [String] = []
  /// Only commits matching this search; `nil` means every commit.
  public var search: HistorySearch? = nil

  public func next() -> LogQuery {
    LogQuery(
      reference: reference,
      path: path,
      followRenames: followRenames,
      maxCount: maxCount,
      skip: skip + maxCount,
      allReferences: allReferences,
      additionalRevisions: additionalRevisions,
      references: references,
      excludedReferences: excludedReferences,
      search: search
    )
  }
}

@MemberwiseInit(.public)
public struct LogPage: Sendable, Hashable {
  public var commits: [Commit]
  public var hasMore: Bool
}
