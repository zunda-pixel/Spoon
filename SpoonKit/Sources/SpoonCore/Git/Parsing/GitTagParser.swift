public import Foundation

/// Parses `git for-each-ref refs/tags` with `tagFormat` into `[Tag]`.
/// Pure and stateless — fixture-tested byte-for-byte.
public enum GitTagParser {
  /// NUL-separated fields, newline-separated records. `%(*objectname)` is
  /// the peeled commit for annotated tags and empty for lightweight ones;
  /// the last field is `1` for a tag with a signature block.
  public static let tagFormat =
    "%(refname:short)%00%(objectname)%00%(*objectname)%00%(creatordate:unix)"
    + "%00%(if)%(contents:signature)%(then)1%(end)"

  public struct ParseError: Error, Sendable {
    public var line: String
  }

  public static func parse(_ data: Data) throws -> [Tag] {
    let text = String(decoding: data, as: UTF8.self)
    return try text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
      let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
      // The signature field is optional, so older fixtures still parse.
      guard fields.count == 4 || fields.count == 5, let objectID = ObjectID(rawValue: String(fields[1])) else {
        throw ParseError(line: String(line))
      }
      let peeled = ObjectID(rawValue: String(fields[2]))
      return Tag(
        name: String(fields[0]),
        target: peeled ?? objectID,
        isAnnotated: peeled != nil,
        isSigned: fields.count == 5 && fields[4] == "1",
        createdAt: TimeInterval(fields[3]).map(Date.init(timeIntervalSince1970:))
      )
    }
  }
}
