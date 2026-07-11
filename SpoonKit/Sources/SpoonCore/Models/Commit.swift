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

/// Parameters for one `git log` page.
public struct LogQuery: Sendable, Hashable {
  /// Ref to walk from; `nil` means HEAD.
  public var reference: String?
  public var maxCount: Int
  public var skip: Int

  public init(reference: String? = nil, maxCount: Int = 500, skip: Int = 0) {
    self.reference = reference
    self.maxCount = maxCount
    self.skip = skip
  }

  public func next() -> LogQuery {
    LogQuery(reference: reference, maxCount: maxCount, skip: skip + maxCount)
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
