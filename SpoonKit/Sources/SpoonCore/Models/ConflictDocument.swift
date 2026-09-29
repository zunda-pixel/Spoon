/// A conflicted working-tree file split at git's conflict markers, so each
/// conflict can be resolved on its own.
public struct ConflictDocument: Sendable, Hashable {
  public enum Segment: Sendable, Hashable {
    /// Lines outside any conflict, each with its line ending.
    case text([String])
    case conflict(ConflictBlock)
  }

  public var segments: [Segment]

  public init(text: String) {
    segments = Self.parse(Self.lines(of: text))
  }

  /// Unresolved conflicts, in file order.
  public var blocks: [ConflictBlock] {
    segments.compactMap {
      if case .conflict(let block) = $0 { block } else { nil }
    }
  }

  /// The file contents, with the conflict at `index` replaced by `choice`.
  /// Other conflicts keep their markers.
  public func text(resolving index: Int, with choice: ConflictChoice) -> String {
    segments.map { segment in
      switch segment {
      case .text(let lines):
        lines.joined()
      case .conflict(let block) where block.index == index:
        block.lines(for: choice).joined()
      case .conflict(let block):
        block.rawLines.joined()
      }
    }.joined()
  }

  /// What to show of the file: every conflict, with up to `context`
  /// unchanged lines around each, and the lines left out between them
  /// counted instead.
  public func outline(context: Int = 3) -> [OutlineItem] {
    var items: [OutlineItem] = []
    for (position, segment) in segments.enumerated() {
      switch segment {
      case .conflict(let block):
        items.append(.conflict(block))
      case .text(let lines):
        let keepsHead = position > 0
        let keepsTail = position + 1 < segments.count
        let head = keepsHead ? min(context, lines.count) : 0
        let tail = keepsTail ? min(context, lines.count - head) : 0
        let omitted = lines.count - head - tail
        if omitted == 0 {
          items.append(.context(lines))
          continue
        }
        if head > 0 { items.append(.context(Array(lines.prefix(head)))) }
        items.append(.omitted(lineCount: omitted))
        if tail > 0 { items.append(.context(Array(lines.suffix(tail)))) }
      }
    }
    return items
  }

  public enum OutlineItem: Sendable, Hashable {
    case context([String])
    case omitted(lineCount: Int)
    case conflict(ConflictBlock)
  }

  // MARK: - Parsing

  /// Splits `text` into lines that keep their `\n`, so joining them
  /// reproduces the file exactly.
  static func lines(of text: String) -> [String] {
    // Split bytes, not Characters: Swift treats "\r\n" as one Character.
    var lines = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
      .map { String(decoding: $0, as: UTF8.self) + "\n" }
    // The split leaves one extra piece after the final newline (or the
    // whole unterminated last line, which must not gain a newline).
    if let last = lines.popLast(), last != "\n" {
      lines.append(String(last.dropLast()))
    }
    return lines
  }

  private enum Marker {
    case start(String)
    case base(String)
    case separator
    case end(String)
  }

  /// Git's default markers are exactly seven characters, optionally
  /// followed by a space and a label.
  private static func marker(in line: String) -> Marker? {
    let content = Substring(line).trimmingSuffix(while: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
    )
    guard let first = content.first, "<|=>".contains(first) else { return nil }
    let run = content.prefix { $0 == first }
    guard run.count == 7 else { return nil }
    let rest = content.dropFirst(7)
    if first == "=" { return rest.isEmpty ? .separator : nil }
    guard rest.isEmpty || rest.first == " " else { return nil }
    let label = String(rest.dropFirst())
    return switch first {
    case "<": .start(label)
    case "|": .base(label)
    default: .end(label)
    }
  }

  private static func parse(_ lines: [String]) -> [Segment] {
    enum Part { case ours, base, theirs }

    var segments: [Segment] = []
    var text: [String] = []
    var block: ConflictBlock?
    var part = Part.ours
    var lineNumber = 0

    func flushText() {
      if !text.isEmpty {
        segments.append(.text(text))
        text = []
      }
    }

    for line in lines {
      lineNumber += 1
      guard var current = block else {
        if case .start(let label) = marker(in: line) {
          block = ConflictBlock(
            index: segments.count { if case .conflict = $0 { true } else { false } },
            startLine: lineNumber, oursLabel: label, rawLines: [line])
          part = .ours
        } else {
          text.append(line)
        }
        continue
      }
      current.rawLines.append(line)
      switch (marker(in: line), part) {
      case (.base(let label), .ours):
        current.baseLabel = label
        current.base = []
        part = .base
      case (.separator, .ours), (.separator, .base):
        part = .theirs
      case (.end(let label), .theirs):
        current.theirsLabel = label
        flushText()
        segments.append(.conflict(current))
        block = nil
        continue
      default:
        switch part {
        case .ours: current.ours.append(line)
        case .base: current.base?.append(line)
        case .theirs: current.theirs.append(line)
        }
      }
      block = current
    }
    // An unterminated conflict is not one git wrote; keep it as text.
    if let block {
      text.append(contentsOf: block.rawLines)
    }
    flushText()
    return segments
  }
}

/// One `<<<<<<< … >>>>>>>` region of a conflicted file.
public struct ConflictBlock: Sendable, Hashable, Identifiable {
  /// Position among the file's conflicts, from 0.
  public var index: Int
  /// 1-based line of the `<<<<<<<` marker.
  public var startLine: Int
  public var oursLabel: String
  public var ours: [String] = []
  /// The common ancestor's lines, present with `merge.conflictStyle=diff3`
  /// or `zdiff3`.
  public var baseLabel: String?
  public var base: [String]?
  public var theirsLabel: String = ""
  public var theirs: [String] = []
  /// Every line of the region, markers included.
  public var rawLines: [String]

  public var id: Int { index }

  public init(index: Int, startLine: Int, oursLabel: String, rawLines: [String]) {
    self.index = index
    self.startLine = startLine
    self.oursLabel = oursLabel
    self.rawLines = rawLines
  }

  func lines(for choice: ConflictChoice) -> [String] {
    switch choice {
    case .ours: ours
    case .theirs: theirs
    case .both: ours + theirs
    }
  }
}

extension Substring {
  fileprivate func trimmingSuffix(while predicate: (Character) -> Bool) -> Substring {
    var trimmed = self
    while let last = trimmed.last, predicate(last) { trimmed = trimmed.dropLast() }
    return trimmed
  }
}

/// How to resolve one conflict region.
public enum ConflictChoice: String, Sendable, Hashable, CaseIterable {
  case ours
  case theirs
  /// Ours followed by theirs.
  case both
}
