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

  public init(text: String, field: Field) {
    self.text = text
    self.field = field
  }

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
public struct LogQuery: Sendable, Hashable {
  /// Ref to walk from; `nil` means HEAD unless `allReferences` is enabled.
  public var reference: String?
  /// Repository-relative path to follow; `nil` means all paths.
  public var path: String?
  /// Keep following `path` across renames (`--follow`). Ignored without `path`.
  public var followRenames: Bool
  public var maxCount: Int
  public var skip: Int
  /// Include commits reachable from every ref.
  public var allReferences: Bool
  /// Explicit reference tips to walk when `allReferences` is false.
  public var references: [String]
  /// References to subtract from an `--all` walk.
  public var excludedReferences: [String]
  /// Extra commit tips to walk, such as detached worktree HEADs.
  public var additionalRevisions: [ObjectID]
  /// Only commits matching this search; `nil` means every commit.
  public var search: HistorySearch?

  public init(
    reference: String? = nil,
    path: String? = nil,
    followRenames: Bool = false,
    maxCount: Int = 500,
    skip: Int = 0,
    allReferences: Bool = false,
    additionalRevisions: [ObjectID] = [],
    references: [String] = [],
    excludedReferences: [String] = [],
    search: HistorySearch? = nil
  ) {
    self.reference = reference
    self.path = path
    self.followRenames = followRenames
    self.maxCount = maxCount
    self.skip = skip
    self.allReferences = allReferences
    self.additionalRevisions = additionalRevisions
    self.references = references
    self.excludedReferences = excludedReferences
    self.search = search
  }

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

public struct LogPage: Sendable, Hashable {
  public var commits: [Commit]
  public var hasMore: Bool

  public init(commits: [Commit], hasMore: Bool) {
    self.commits = commits
    self.hasMore = hasMore
  }
}
