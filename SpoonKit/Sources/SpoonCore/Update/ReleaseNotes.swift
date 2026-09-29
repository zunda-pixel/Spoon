import Foundation

/// Release notes split into the Markdown blocks GitHub's generated notes use,
/// since `Text` renders only inline Markdown (no headings or lists).
public enum ReleaseNotes {
  public enum Block: Sendable, Hashable {
    case heading(level: Int, text: String)
    case bullet(String)
    case paragraph(String)
  }

  public static func blocks(from markdown: String) -> [Block] {
    var blocks: [Block] = []
    var paragraph: [String] = []

    func flushParagraph() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: " ")))
        paragraph = []
      }
    }

    for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty {
        flushParagraph()
      } else if let heading = heading(line) {
        flushParagraph()
        blocks.append(heading)
      } else if line.hasPrefix("* ") || line.hasPrefix("- ") || line.hasPrefix("+ ") {
        flushParagraph()
        blocks.append(.bullet(String(line.dropFirst(2))))
      } else {
        paragraph.append(line)
      }
    }
    flushParagraph()
    return blocks
  }

  private static func heading(_ line: String) -> Block? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
  }
}
