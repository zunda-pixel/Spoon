public import Foundation

/// Parses `git log -z` output in `logFormat` into `[Commit]`.
/// Pure and stateless — fixture-tested byte-for-byte.
public enum GitLogParser {
  /// Unit-separator (0x1F) between fields; `-z` NUL-terminates records.
  /// Subjects cannot contain NUL, and 0x1F is vanishingly rare in practice —
  /// the parser tolerates extra separators by treating the tail as subject.
  public static let logFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%ct%x1f%s"

  public struct ParseError: Error, Sendable {
    public var record: String
  }

  public static func parse(_ data: Data) throws -> [Commit] {
    let text = String(decoding: data, as: UTF8.self)
    return try text.split(separator: "\0", omittingEmptySubsequences: true).map { record in
      let fields = record.split(separator: "\u{1f}", maxSplits: 6, omittingEmptySubsequences: false)
      guard
        fields.count == 7,
        let oid = ObjectID(rawValue: String(fields[0])),
        let authoredAt = TimeInterval(fields[4]),
        let committedAt = TimeInterval(fields[5])
      else {
        throw ParseError(record: String(record))
      }
      let parents = fields[1]
        .split(separator: " ", omittingEmptySubsequences: true)
        .compactMap { ObjectID(rawValue: String($0)) }
      return Commit(
        oid: oid,
        parents: parents,
        subject: String(fields[6]),
        authorName: String(fields[2]),
        authorEmail: String(fields[3]),
        authoredAt: Date(timeIntervalSince1970: authoredAt),
        committedAt: Date(timeIntervalSince1970: committedAt)
      )
    }
  }
}
