import Foundation

enum UntrackedDiffBuilder {
  static let maximumBytes = 2 * 1024 * 1024

  static func make(path: String, data: Data) -> FileDiff {
    if data.prefix(8192).contains(0) {
      return FileDiff(path: path, kind: .added, isBinary: true)
    }

    let text = String(decoding: data.prefix(maximumBytes), as: UTF8.self)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
    let endsWithNewline = text.hasSuffix("\n")
    if endsWithNewline {
      lines = lines.dropLast()
    }

    var diffLines = lines.enumerated().map { index, line in
      DiffLine(kind: .addition, text: String(line), newLine: index + 1)
    }
    if !endsWithNewline, !diffLines.isEmpty {
      diffLines.append(DiffLine(kind: .noNewlineMarker, text: "\\ No newline at end of file"))
    }
    let hunk = Hunk(
      header: "@@ -0,0 +1,\(lines.count) @@",
      oldStart: 0,
      oldCount: 0,
      newStart: 1,
      newCount: lines.count,
      lines: diffLines
    )
    return FileDiff(path: path, kind: .added, hunks: diffLines.isEmpty ? [] : [hunk])
  }
}
