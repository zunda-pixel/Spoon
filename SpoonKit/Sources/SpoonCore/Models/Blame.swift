public import Foundation

/// The commit that last changed one or more blamed lines.
public struct BlameCommit: Sendable, Hashable {
  public var oid: ObjectID
  public var authorName: String
  public var authoredAt: Date
  public var summary: String

  public init(oid: ObjectID, authorName: String, authoredAt: Date, summary: String) {
    self.oid = oid
    self.authorName = authorName
    self.authoredAt = authoredAt
    self.summary = summary
  }

  /// Git reports working-tree edits under the all-zero object ID.
  public var isUncommitted: Bool { oid.rawValue.allSatisfy { $0 == "0" } }
}

/// One line of `git blame` output.
public struct BlameLine: Sendable, Hashable, Identifiable {
  /// 1-based line number in the blamed file.
  public var lineNumber: Int
  public var commit: BlameCommit
  public var text: String

  public init(lineNumber: Int, commit: BlameCommit, text: String) {
    self.lineNumber = lineNumber
    self.commit = commit
    self.text = text
  }

  public var id: Int { lineNumber }
}
