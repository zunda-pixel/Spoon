import Foundation
public import MemberwiseInit

/// A `git grep` over the working tree or one revision.
@MemberwiseInit(.public)
public struct CodeSearchQuery: Sendable, Hashable {
  public enum Syntax: String, Sendable, Hashable, CaseIterable {
    /// The pattern is plain text (`--fixed-strings`).
    case literal
    /// POSIX extended regular expression (`--extended-regexp`).
    case regularExpression
  }

  public var pattern: String
  /// Commit, branch, or tag to search; `nil` searches the working tree.
  public var revision: String? = nil
  public var matchesCase: Bool = false
  public var matchesWholeWord: Bool = false
  public var syntax: Syntax = .literal
  /// Also search untracked files; ignored for a revision.
  public var includesUntracked: Bool = false
  /// Pathspecs such as `*.swift` or `Sources/`; empty searches everything.
  public var paths: [String] = []

  /// Most matches `git grep` reports for one file.
  static let maxMatchesPerFile = 200

  var arguments: [String] {
    var arguments = [
      "grep", "-z", "--line-number", "--column", "-I", "--no-color", "--full-name",
      "--max-count=\(Self.maxMatchesPerFile)",
    ]
    if !matchesCase { arguments.append("--ignore-case") }
    if matchesWholeWord { arguments.append("--word-regexp") }
    arguments.append(syntax == .literal ? "--fixed-strings" : "--extended-regexp")
    if includesUntracked && revision == nil { arguments.append("--untracked") }
    arguments += ["-e", pattern]
    if let revision { arguments.append(revision) }
    arguments.append("--")
    arguments += paths
    return arguments
  }

  /// Where the pattern matches in one line of a result, for highlighting.
  /// Approximate for regular expressions, which Foundation reads slightly
  /// differently from git; an unreadable one highlights nothing.
  public func matchRanges(in text: String) -> [Range<String.Index>] {
    let escaped =
      syntax == .literal ? NSRegularExpression.escapedPattern(for: pattern) : pattern
    let bounded = matchesWholeWord ? "\\b(?:\(escaped))\\b" : escaped
    guard
      !pattern.isEmpty,
      let expression = try? NSRegularExpression(
        pattern: bounded, options: matchesCase ? [] : [.caseInsensitive])
    else { return [] }
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
      .compactMap { Range($0.range, in: text) }
      .filter { !$0.isEmpty }
  }
}

/// One matching line.
@MemberwiseInit(.public)
public struct CodeSearchMatch: Sendable, Hashable, Identifiable {
  /// Repository-relative path.
  public var path: String
  public var lineNumber: Int
  /// 1-based byte column of the first match in the line.
  public var column: Int
  public var text: String

  public var id: String { "\(path):\(lineNumber)" }
}

@MemberwiseInit(.public)
public struct CodeSearchResult: Sendable, Hashable {
  public var matches: [CodeSearchMatch]
  /// More lines matched than were kept.
  public var isTruncated: Bool

  /// Matches grouped by file, in the order git reported the files.
  public var files: [(path: String, matches: [CodeSearchMatch])] {
    var order: [String] = []
    var byPath: [String: [CodeSearchMatch]] = [:]
    for match in matches {
      if byPath[match.path] == nil { order.append(match.path) }
      byPath[match.path, default: []].append(match)
    }
    return order.map { ($0, byPath[$0] ?? []) }
  }

  /// Parses `git grep -z --line-number --column` output: one
  /// `path NUL line NUL column NUL text` record per line. With a revision,
  /// git prefixes each path with `<revision>:`.
  static func parse(_ output: Data, revision: String?, limit: Int) -> Self {
    var matches: [CodeSearchMatch] = []
    let prefix = revision.map { $0 + ":" }
    // Split bytes, not Characters: Swift treats "\r\n" as one Character.
    for record in output.split(separator: UInt8(ascii: "\n")) {
      guard matches.count < limit else { return Self(matches: matches, isTruncated: true) }
      let fields = record.split(separator: 0, maxSplits: 3, omittingEmptySubsequences: false)
        .map { String(decoding: $0, as: UTF8.self) }
      guard fields.count == 4, let line = Int(fields[1]), let column = Int(fields[2]) else {
        continue
      }
      var path = Substring(fields[0])
      if let prefix, path.hasPrefix(prefix) { path = path.dropFirst(prefix.count) }
      var text = Substring(fields[3])
      if text.hasSuffix("\r") { text = text.dropLast() }
      matches.append(
        CodeSearchMatch(
          path: String(path), lineNumber: line, column: column, text: String(text))
      )
    }
    return Self(matches: matches, isTruncated: false)
  }
}
