public import Foundation

/// Parses unified diff output from `git diff` / `git diff-tree -p`
/// (with `core.quotePath=false`). Pure and stateless.
public enum GitDiffParser {
  public struct ParseError: Error, Sendable {
    public var line: String
  }

  public static func parse(_ data: Data) throws -> [FileDiff] {
    let text = String(decoding: data, as: UTF8.self)
    var files: [FileDiff] = []
    var current: FileDiff?
    var currentHunk: Hunk?
    // Hunk bodies are delimited by the header's line counts, not by prefix
    // sniffing — a following `--- a/x` header is indistinguishable from a
    // deletion line by prefix alone.
    var oldRemaining = 0
    var newRemaining = 0
    var oldLine = 0
    var newLine = 0

    func closeHunk() {
      if let hunk = currentHunk, var file = current {
        file.hunks.append(hunk)
        current = file
      }
      currentHunk = nil
    }

    func closeFile() {
      closeHunk()
      if let file = current {
        files.append(file)
      }
      current = nil
    }

    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
    if text.hasSuffix("\n") {
      lines = lines.dropLast()  // drop the empty piece after the final newline
    }

    for line in lines {
      if currentHunk != nil, oldRemaining > 0 || newRemaining > 0 {
        switch line.first {
        case " ":
          currentHunk?.lines.append(
            DiffLine(
              kind: .context, text: String(line.dropFirst()), oldLine: oldLine, newLine: newLine)
          )
          oldLine += 1
          newLine += 1
          oldRemaining -= 1
          newRemaining -= 1
        case "-":
          currentHunk?.lines.append(
            DiffLine(kind: .deletion, text: String(line.dropFirst()), oldLine: oldLine)
          )
          oldLine += 1
          oldRemaining -= 1
        case "+":
          currentHunk?.lines.append(
            DiffLine(kind: .addition, text: String(line.dropFirst()), newLine: newLine)
          )
          newLine += 1
          newRemaining -= 1
        case "\\":
          currentHunk?.lines.append(DiffLine(kind: .noNewlineMarker, text: String(line)))
        case nil:
          // Lenient: a bare empty line counts as an empty context line
          // (git emits " " but some tools strip trailing whitespace).
          currentHunk?.lines.append(
            DiffLine(kind: .context, text: "", oldLine: oldLine, newLine: newLine)
          )
          oldLine += 1
          newLine += 1
          oldRemaining -= 1
          newRemaining -= 1
        default:
          throw ParseError(line: String(line))
        }
        continue
      }

      // A `\ No newline at end of file` for the hunk's very last line
      // arrives after the counts are exhausted.
      if currentHunk != nil, line.first == "\\" {
        currentHunk?.lines.append(DiffLine(kind: .noNewlineMarker, text: String(line)))
        continue
      }
      closeHunk()

      if line.hasPrefix("diff --git ") {
        closeFile()
        current = FileDiff(path: "", hunks: [])
        continue
      }
      guard current != nil else { continue }  // preamble (e.g. diff-tree oid line)

      if line.hasPrefix("@@ ") {
        guard let header = parseHunkHeader(line) else {
          throw ParseError(line: String(line))
        }
        currentHunk = header
        oldRemaining = header.oldCount
        newRemaining = header.newCount
        oldLine = header.oldStart
        newLine = header.newStart
      } else if let value = value(of: line, after: "--- ") {
        if value != "/dev/null", current?.path.isEmpty == true {
          current?.path = stripPrefix(value, "a/")
        }
      } else if let value = value(of: line, after: "+++ ") {
        if value == "/dev/null" {
          current?.kind = .deleted
        } else {
          current?.path = stripPrefix(value, "b/")
        }
      } else if let value = value(of: line, after: "rename from ") {
        current?.kind = .renamed
        current?.oldPath = value
      } else if let value = value(of: line, after: "rename to ") {
        current?.path = value
      } else if let value = value(of: line, after: "copy from ") {
        current?.kind = .copied
        current?.oldPath = value
      } else if let value = value(of: line, after: "copy to ") {
        current?.path = value
      } else if let value = value(of: line, after: "new file mode ") {
        current?.kind = .added
        current?.newMode = value
      } else if let value = value(of: line, after: "deleted file mode ") {
        current?.kind = .deleted
        current?.oldMode = value
      } else if let value = value(of: line, after: "old mode ") {
        current?.oldMode = value
      } else if let value = value(of: line, after: "new mode ") {
        current?.newMode = value
      } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
        current?.isBinary = true
      }
      // "index …", "similarity index …" and anything else: ignored.
    }
    closeFile()
    return files
  }

  /// `@@ -12,5 +14,6 @@ optional section` (counts default to 1).
  private static func parseHunkHeader(_ line: Substring) -> Hunk? {
    let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
    guard
      parts.count >= 4,
      parts[0] == "@@",
      let old = parseRange(parts[1], expecting: "-"),
      let new = parseRange(parts[2], expecting: "+")
    else { return nil }
    return Hunk(
      header: String(line),
      oldStart: old.start,
      oldCount: old.count,
      newStart: new.start,
      newCount: new.count,
      lines: []
    )
  }

  private static func parseRange(_ field: Substring, expecting sign: Character) -> (
    start: Int, count: Int
  )? {
    guard field.first == sign else { return nil }
    let numbers = field.dropFirst().split(separator: ",")
    guard let start = numbers.first.flatMap({ Int($0) }) else { return nil }
    let count = numbers.count > 1 ? Int(numbers[1]) ?? 1 : 1
    return (start, count)
  }

  private static func value(of line: Substring, after prefix: String) -> String? {
    guard line.hasPrefix(prefix) else { return nil }
    return String(line.dropFirst(prefix.count))
  }

  private static func stripPrefix(_ value: String, _ prefix: String) -> String {
    value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
  }
}
