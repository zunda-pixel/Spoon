import Foundation

/// Parses `git blame --porcelain` output. Commit headers appear only on
/// the first line attributed to each commit, so they are remembered by OID.
enum GitBlameParser {
  static func parse(_ data: Data) -> [BlameLine] {
    let text = String(decoding: data, as: UTF8.self)
    var commits: [ObjectID: BlameCommit] = [:]
    var lines: [BlameLine] = []
    var current: (oid: ObjectID, finalLine: Int)?
    var author = ""
    var authoredAt = Date(timeIntervalSince1970: 0)
    var summary = ""

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if rawLine.hasPrefix("\t") {
        guard let (oid, finalLine) = current else { continue }
        let commit =
          commits[oid]
          ?? BlameCommit(oid: oid, authorName: author, authoredAt: authoredAt, summary: summary)
        commits[oid] = commit
        lines.append(
          BlameLine(lineNumber: finalLine, commit: commit, text: String(rawLine.dropFirst()))
        )
        current = nil
        continue
      }
      let fields = rawLine.split(separator: " ", maxSplits: 1)
      guard let key = fields.first else { continue }
      let value = fields.count > 1 ? String(fields[1]) : ""
      switch key {
      case "author": author = value
      case "author-time": authoredAt = Date(timeIntervalSince1970: TimeInterval(value) ?? 0)
      case "summary": summary = value
      default:
        // `<oid> <orig-line> <final-line> [<group-size>]` starts each line.
        let header = rawLine.split(separator: " ")
        if header.count >= 3, let oid = ObjectID(rawValue: String(header[0])),
          oid.rawValue.count >= 40, let finalLine = Int(header[2])
        {
          current = (oid, finalLine)
          if commits[oid] == nil {
            author = ""
            authoredAt = Date(timeIntervalSince1970: 0)
            summary = ""
          }
        }
      }
    }
    return lines
  }
}
