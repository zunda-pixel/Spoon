import Foundation

enum GitStashParser {
  static func parse(_ data: Data) -> [Stash] {
    String(decoding: data, as: UTF8.self)
      .split(separator: "\0", omittingEmptySubsequences: true)
      .compactMap(parseRecord)
  }

  private static func parseRecord(_ record: Substring) -> Stash? {
    let fields = record.split(
      separator: "\u{1f}",
      maxSplits: 3,
      omittingEmptySubsequences: false
    )
    guard
      fields.count == 4,
      let target = ObjectID(rawValue: String(fields[0])),
      fields[2].hasPrefix("stash@{"),
      fields[2].hasSuffix("}"),
      let index = Int(fields[2].dropFirst("stash@{".count).dropLast()),
      index >= 0
    else {
      return nil
    }
    let parentFields = fields[1].split(separator: " ", omittingEmptySubsequences: true)
    let parents = parentFields.compactMap { ObjectID(rawValue: String($0)) }
    guard parents.count == parentFields.count else { return nil }
    return Stash(
      index: index,
      target: target,
      helperCommitOIDs: Array(parents.dropFirst()),
      message: String(fields[3])
    )
  }
}
