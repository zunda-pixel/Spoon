import Foundation

/// Parses `git range-diff --no-color` output. Each pairing is a header such as
/// `2:  8e3c00b ! 2:  6058041 add two`, and a changed pairing is followed by
/// its patch-of-patches indented by four spaces.
enum GitRangeDiffParser {
  static func parse(_ output: String) -> [RangeDiffEntry] {
    var entries: [RangeDiffEntry] = []
    for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if let entry = header(line) {
        entries.append(entry)
      } else if !entries.isEmpty, line.hasPrefix("    ") {
        entries[entries.count - 1].patchDiff.append(String(line.dropFirst(4)))
      } else if !entries.isEmpty, line.isEmpty, !entries[entries.count - 1].patchDiff.isEmpty {
        entries[entries.count - 1].patchDiff.append("")
      }
    }
    for index in entries.indices {
      while entries[index].patchDiff.last?.isEmpty == true {
        entries[index].patchDiff.removeLast()
      }
    }
    return entries
  }

  private static func header(_ line: String) -> RangeDiffEntry? {
    // <pos>: <oid> <relation> <pos>: <oid> <subject>, `-` marking a missing side.
    let pattern = /^(\d+|-):\s+([0-9a-f]+|-+)\s+([=!<>])\s+(\d+|-):\s+([0-9a-f]+|-+)\s?(.*)$/
    guard let match = line.wholeMatch(of: pattern) else { return nil }
    let relation: RangeDiffEntry.Relation =
      switch match.output.3 {
      case "=": .unchanged
      case "!": .changed
      case "<": .removed
      default: .added
      }
    func oid(_ part: Substring) -> String? {
      part.allSatisfy { $0 == "-" } ? nil : String(part)
    }
    return RangeDiffEntry(
      relation: relation,
      oldPosition: Int(match.output.1),
      oldOID: oid(match.output.2),
      newPosition: Int(match.output.4),
      newOID: oid(match.output.5),
      subject: String(match.output.6)
    )
  }
}
