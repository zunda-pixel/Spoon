public import Foundation

public enum GitReflogParser {
  public static let format = "%H%x1f%gd%x1f%gs%x1f%an%x1f%ae%x1f%at"

  public struct ParseError: Error, Sendable {
    public var record: String
  }

  public static func parse(_ data: Data) throws -> [ReflogEntry] {
    let text = String(decoding: data, as: UTF8.self)
    return try text.split(separator: "\0", omittingEmptySubsequences: true).map { record in
      let fields = record.split(
        separator: "\u{1f}",
        maxSplits: 5,
        omittingEmptySubsequences: false
      )
      guard
        fields.count == 6,
        let oid = ObjectID(rawValue: String(fields[0])),
        let timestamp = TimeInterval(fields[5])
      else {
        throw ParseError(record: String(record))
      }
      return ReflogEntry(
        oid: oid,
        selector: String(fields[1]),
        subject: String(fields[2]),
        authorName: String(fields[3]),
        authorEmail: String(fields[4]),
        date: Date(timeIntervalSince1970: timestamp)
      )
    }
  }
}
