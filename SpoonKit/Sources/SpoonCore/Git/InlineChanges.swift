/// Finds the changed words within modified lines of a hunk, for highlighting
/// them the way code review tools do.
///
/// Within each run of deleted lines directly followed by added lines, the
/// n-th deletion is paired with the n-th addition and their tokens (words,
/// whitespace runs, single punctuation marks) are compared with a longest
/// common subsequence. Pairs with nothing in common are left unhighlighted,
/// since marking the whole line adds no information.
public enum InlineChanges {
  /// Changed character ranges (in `Character` offsets of `DiffLine.text`),
  /// keyed by line offset within the hunk.
  public static func ranges(in hunk: Hunk) -> [Int: [Range<Int>]] {
    var result: [Int: [Range<Int>]] = [:]
    let lines = hunk.lines
    var index = 0
    while index < lines.count {
      guard lines[index].kind == .deletion else {
        index += 1
        continue
      }
      let deletions = run(of: .deletion, in: lines, from: index)
      let additions = run(of: .addition, in: lines, from: deletions.upperBound)
      for (old, new) in zip(deletions, additions) {
        if let (oldRanges, newRanges) = changedRanges(lines[old].text, lines[new].text) {
          result[old] = oldRanges
          result[new] = newRanges
        }
      }
      index = max(additions.upperBound, deletions.upperBound)
    }
    return result
  }

  private static func run(of kind: DiffLine.Kind, in lines: [DiffLine], from start: Int)
    -> Range<Int>
  {
    var end = start
    while end < lines.count, lines[end].kind == kind { end += 1 }
    return start..<end
  }

  /// Longer lines are not compared: the quadratic LCS would be slow and the
  /// highlight rarely helps there.
  private static let maxTokens = 300

  static func changedRanges(_ old: String, _ new: String) -> ([Range<Int>], [Range<Int>])? {
    let oldTokens = tokens(of: old)
    let newTokens = tokens(of: new)
    guard oldTokens.count <= maxTokens, newTokens.count <= maxTokens else { return nil }
    let (oldKept, newKept) = commonTokens(oldTokens.map(\.text), newTokens.map(\.text))
    let sharesContent = oldKept.contains { !oldTokens[$0].isWhitespace }
    guard sharesContent else { return nil }
    let oldRanges = changed(oldTokens, keeping: oldKept)
    let newRanges = changed(newTokens, keeping: newKept)
    guard !oldRanges.isEmpty || !newRanges.isEmpty else { return nil }
    return (oldRanges, newRanges)
  }

  private static func changed(_ tokens: [Token], keeping kept: Set<Int>) -> [Range<Int>] {
    merged(tokens.indices.filter { !kept.contains($0) }.map { tokens[$0].range })
  }

  struct Token {
    var text: String
    var range: Range<Int>
    var isWhitespace: Bool
  }

  static func tokens(of text: String) -> [Token] {
    var tokens: [Token] = []
    var current = ""
    var start = 0
    var currentClass: Int?
    for (offset, character) in text.enumerated() {
      let isWord = character.isLetter || character.isNumber || character == "_"
      let characterClass = character.isWhitespace ? 0 : isWord ? 1 : 2
      // Punctuation is always its own token; letters and whitespace group.
      if characterClass == currentClass, characterClass != 2 {
        current.append(character)
        continue
      }
      if let currentClass {
        tokens.append(
          Token(text: current, range: start..<offset, isWhitespace: currentClass == 0))
      }
      current = String(character)
      start = offset
      currentClass = characterClass
    }
    if let currentClass {
      let range = start..<(start + current.count)
      tokens.append(Token(text: current, range: range, isWhitespace: currentClass == 0))
    }
    return tokens
  }

  /// Indices of the tokens on each side that belong to one longest common subsequence.
  private static func commonTokens(_ a: [String], _ b: [String]) -> (Set<Int>, Set<Int>) {
    guard !a.isEmpty, !b.isEmpty else { return ([], []) }
    var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
      for j in stride(from: b.count - 1, through: 0, by: -1) {
        lengths[i][j] =
          a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
      }
    }
    var keptA: Set<Int> = []
    var keptB: Set<Int> = []
    var i = 0
    var j = 0
    while i < a.count, j < b.count {
      if a[i] == b[j] {
        keptA.insert(i)
        keptB.insert(j)
        i += 1
        j += 1
      } else if lengths[i + 1][j] >= lengths[i][j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    return (keptA, keptB)
  }

  private static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    for range in ranges {
      if let last = result.last, last.upperBound == range.lowerBound {
        result[result.count - 1] = last.lowerBound..<range.upperBound
      } else {
        result.append(range)
      }
    }
    return result
  }
}
