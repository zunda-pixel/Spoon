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
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard
      fields.count == 2,
      let open = fields[0].firstIndex(of: "{"),
      let close = fields[0].firstIndex(of: "}"),
      open < close,
      let index = Int(fields[0][fields[0].index(after: open)..<close])
    else {
      return nil
    }
    return Stash(index: index, message: String(fields[1]))
  }
}
