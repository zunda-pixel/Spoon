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
      maxSplits: 2,
      omittingEmptySubsequences: false
    )
    guard
      fields.count == 3,
      let target = ObjectID(rawValue: String(fields[0])),
      fields[1].hasPrefix("stash@{"),
      fields[1].hasSuffix("}"),
      let index = Int(fields[1].dropFirst("stash@{".count).dropLast()),
      index >= 0
    else {
      return nil
    }
    return Stash(index: index, target: target, message: String(fields[2]))
  }
}
